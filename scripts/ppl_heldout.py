#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Teacher-forced perplexity on the corpus heldout files, inside the oMLX venv.

Loads the quant through oMLX's own runtime. For qwen4_exp checkpoints
(DeltaNet + QSA + PLE n-gram) there is no mlx-lm model module, so the load
goes through the vendored mlx-vlm registration exactly at the oMLX server
stack (pre-load patches, forced sanitize, mmap PLE). For DeepSeek V4.1 it
goes through the V4.1 loader with Engram SSD offload and optional routed-
expert offload, so a 128 GB host can score without materializing the full
Engram or expert set.

Run it once per model — one process per quant, the large loads don't
co-reside:

    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/Qwen3.8-Flash-Next-oQ5e-stock \
        --files eval/heldout-se.txt eval/heldout-general.txt

    OQ_PPL_EXPERT_FRACTION=0.25 \
    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/DeepSeek-V4.1-Flash-1017-oQ3e-se-q3-ngram8 \
        --files eval/heldout-se2.txt eval/heldout-se.txt eval/heldout-general.txt \
        --chunk 2048

Teacher anchors (source-model reference; run once, reuse for every quant):

    # one-time, against the source checkpoint on the quant host
    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model <source-checkpoint> \
        --files eval/heldout-se2.txt eval/heldout-se.txt eval/heldout-general.txt \
        --chunk 2048 --teacher-save ~/oqup/teacher-anchors-se2-2048.npz

    # every later quant run adds the absolute comparison
    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/<quant> --files ... --chunk 2048 \
        --teacher ~/oqup/teacher-anchors-se2-2048.npz

The anchor file stores the teacher's per-token argmax and NLL, so the two
models never have to co-reside in RAM (they cannot on a 128 GB host). The
student run reports teacher NLL/token, the NLL delta against it, and top-1
agreement with the teacher's argmax — the absolute preservation measure.
Anchors are keyed by file sha256 and chunk width; either changing means
rebuild the anchors. The omlx_oq4e.sh build tail automates this: it
content-addresses the anchor under $OQUP and builds it on first use, then
reuses it for every later build.

The script needs the quant host's `~/dev/omlx` venv python (it imports
`omlx` and `mlx_vlm`, both pinned there). Only PPL deltas between runs
matter: same chunking for both models, and the first pair should use the
same files. Per-chunk NLL lines let you spot WHICH heldout region diverges,
not just the average. `heldout-se.txt` is the domain-relevant comparison;
`heldout-general.txt` is where stock shouldn't be sacrificed.

For DeepSeek V4.1, `--moe-resident-fraction` (or
`OQ_PPL_EXPERT_FRACTION`) controls how much of the routed-expert set stays
resident; the rest streams from the checkpoint. The default 0.25 matches the
quant host's safe serving range. Set it to 1.0 on a host with enough RAM.
"""

import argparse
import hashlib
import json
import math
import os
import sys
import time
from pathlib import Path

import mlx.core as mx
import numpy as np

DEFAULT_CHUNK = 512  # historical default; every recorded run passes --chunk 2048


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load_omlx_quant(model_path: str, *, moe_resident_fraction: float | None = None):
    """Load an oQ quant the way the oMLX server does for its model family.

    qwen4_exp: the text arch (GatedDeltaNet + QSA + PLE n-gram) has no mlx-lm
    model module, so mlx-lm's registry raises "Model type qwen4_exp not
    supported". The arch lives vendored inside omlx for mlx-vlm and is wired
    by the for_vlm pre-load dispatcher (the same recipe the build's
    calibration loads use). Forced sanitize is mandatory for MLX-format
    files: mlx-vlm otherwise skips Model.sanitize and the
    `model.language_model.*` weight keys never bind.

    deepseek_v41: the V4.1 loader reads converted or source checkpoints with
    Engram on SSD and, when asked, keeps only a fraction of each layer's
    routed experts resident. That is the same runtime used by the server, so
    PPL remains comparable with serving without fitting 400+ GB in RAM.
    """
    path = Path(model_path).expanduser()
    if not path.is_dir():
        raise FileNotFoundError(model_path)
    config = json.loads((path / "config.json").read_text())
    model_type = str(config.get("model_type", "")).lower().replace("-", "_")
    if model_type == "deepseek_v41":
        from omlx.patches.deepseek_v41.loading import load as v41_load

        kwargs = {"engram_ssd_offload": True}
        if moe_resident_fraction is not None:
            kwargs["moe_expert_offload_resident_fraction"] = moe_resident_fraction
        model, processor = v41_load(str(path), **kwargs)
        tokenizer = getattr(processor, "tokenizer", processor)
        return model, tokenizer

    from omlx.engine.vlm import _force_qwen4_exp_sanitize_on_load
    from omlx.oq import _calibration_model_settings
    from omlx.utils.model_loading import (
        maybe_apply_pre_load_patches,
        materialize_lazy_state,
    )

    settings = _calibration_model_settings(
        config, has_mtp_heads=False, has_mtp_weights=False
    )
    if settings is None:
        raise ValueError(
            "only qwen4_exp and deepseek_v41 checkpoints are wired through "
            f"this loader; config says {config.get('model_type')!r}"
        )
    maybe_apply_pre_load_patches(str(path), model_settings=settings, for_vlm=True)

    import mlx_vlm
    from mlx_vlm.utils import load as vlm_load

    with _force_qwen4_exp_sanitize_on_load(path):
        loaded = vlm_load(
            str(path),
            trust_remote_code=False,
            lazy=True,
        )
    model = loaded[0]
    processor = loaded[-1]
    tokenizer = getattr(processor, "tokenizer", processor)
    materialize_lazy_state(model)
    del mlx_vlm
    return model, tokenizer


def forward_logits(model, ids: list[int]):
    """Run one token chunk through the model; return logits [T, vocab] (float32).

    The vendored qwen4_exp trunk unpacks ``batch_size, seq_length = inputs.shape``
    and needs the batch dim, and returns a ``LanguageModelOutput`` whose
    ``.logits`` attribute carries the scores — not a bare tensor.
    """
    arr = mx.array(ids)[None]
    errors = []
    out = None
    attempts = (
        ("model.language_model(inputs)", lambda: model.language_model(arr)),
        ("model(inputs)", lambda: model(arr)),
        ("model.forward(inputs)", lambda: model.forward(arr)),
    )
    for name, attempt in attempts:
        try:
            out = attempt()
            if out is not None and hasattr(out, "logits"):
                out = out.logits
            if out is None:
                errors.append(f"{name}: returned None")
                continue
            break
        except Exception as exc:  # report every convention's error, not just the last
            errors.append(f"{name}: {type(exc).__name__}: {exc}")
    if not isinstance(out, (mx.array,)):
        if out is not None:
            out = None if not hasattr(out, "shape") else out
    if out is None:
        raise RuntimeError("no forward convention worked:\n  " + "\n  ".join(errors))
    import mlx.nn as nn

    return nn.log_softmax(out.reshape(-1, out.shape[-1]).astype(mx.float32), axis=-1)


def score_file(model, tokenizer, path: Path, chunk: int, *, teacher=None, collect=False):
    """Return (total_nll, total_scored_tokens, extra) for a text file.

    ``teacher`` is a per-file anchor dict (targets / argmax / nll from
    ``--teacher-save``): the function verifies token-stream alignment, sums
    the teacher's NLL and counts top-1 agreement against its argmax.
    ``collect`` fills ``extra`` with this model's per-token arrays so the
    caller can write a new anchor file.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 0.0, 0, {}

    ids = tokenizer.encode(text)
    if chunk < 2:
        chunk = DEFAULT_CHUNK
    nll_sum = 0.0
    scored = 0
    teacher_nll = 0.0
    agree = 0
    t_off = 0
    col_targets: list[np.ndarray] = []
    col_argmax: list[np.ndarray] = []
    col_nll: list[np.ndarray] = []
    t0 = time.time()
    for start in range(0, max(len(ids) - 1, 0), chunk):
        window = ids[start : start + chunk]
        if len(window) < 2:
            break
        logp = forward_logits(model, window[:-1])
        targets = mx.array(window[1:])
        tok_nll = -logp[mx.arange(targets.shape[0]), targets]
        s = float(mx.sum(tok_nll).item())
        nll_sum += s
        scored += targets.shape[0]

        if collect:
            col_targets.append(np.asarray(window[1:], dtype=np.int32))
            col_argmax.append(np.array(mx.argmax(logp, axis=-1), dtype=np.int32))
            col_nll.append(np.array(tok_nll, dtype=np.float64))

        if teacher is not None:
            n = targets.shape[0]
            t_targets = teacher["targets"][t_off : t_off + n]
            if not np.array_equal(np.asarray(window[1:], dtype=np.int32), t_targets):
                raise SystemExit(
                    f"{path.name}: token stream diverged from the teacher anchor at "
                    f"offset {start} — the file or tokenizer changed; rebuild the anchor"
                )
            t_am = teacher["argmax"][t_off : t_off + n]
            t_nll = teacher["nll"][t_off : t_off + n]
            teacher_nll += float(t_nll.sum())
            agree += int(mx.sum(mx.argmax(logp, axis=-1) == mx.array(t_am)).item())
            t_off += n

        if scored % (chunk * 8) < chunk:
            n, s = scored, max(time.time() - t0, 1e-9)
            print(f"  {path.name}: {n} tokens scored ({n / s:.0f} tok/s), running PPL {math.exp(nll_sum / n):.3f}", file=sys.stderr)
    if scored:
        print(
            f"  {path.name}: {scored} tokens in {time.time() - t0:.1f}s -> "
            f"NLL/token {nll_sum / scored:.4f} | PPL {math.exp(nll_sum / scored):.4f} | "
            f"bits/token {(nll_sum / scored) / math.log(2):.4f}",
            file=sys.stderr,
        )
    extra: dict[str, object] = {}
    if teacher is not None:
        extra["teacher_nll"] = teacher_nll
        extra["agree"] = agree
    if collect:
        extra["targets"] = np.concatenate(col_targets) if col_targets else np.zeros(0, np.int32)
        extra["argmax"] = np.concatenate(col_argmax) if col_argmax else np.zeros(0, np.int32)
        extra["nll"] = np.concatenate(col_nll) if col_nll else np.zeros(0, np.float64)
    return nll_sum, scored, extra


def main() -> int:
    ap = argparse.ArgumentParser(description="Heldout perplexity for an oMLX-loaded quant.")
    ap.add_argument("--model", required=True, help="quant dir (config.json + safetensors) or HF id")
    ap.add_argument("--files", required=True, nargs="+", help="heldout text files to score, one by one")
    ap.add_argument("--chunk", type=int, default=DEFAULT_CHUNK, help="tokens per scoring window (default 512)")
    ap.add_argument(
        "--moe-resident-fraction",
        type=float,
        default=float(os.environ.get("OQ_PPL_EXPERT_FRACTION", "0.25")),
        help="DeepSeek V4.1 routed-expert resident fraction (default 0.25; "
        "OQ_PPL_EXPERT_FRACTION overrides)",
    )
    anchors_group = ap.add_mutually_exclusive_group()
    anchors_group.add_argument(
        "--teacher",
        metavar="NPZ",
        help="teacher anchors written by --teacher-save on the source checkpoint; "
        "adds teacher NLL, NLL delta and top-1 agreement columns",
    )
    anchors_group.add_argument(
        "--teacher-save",
        metavar="NPZ",
        help="write per-token teacher anchors for --model (run once on the source checkpoint)",
    )
    args = ap.parse_args()

    for f in args.files:
        if not Path(f).is_file():
            print(f"missing file: {f}", file=sys.stderr)
            return 2

    anchor_meta = None
    anchor_arrays = None
    if args.teacher:
        apath = Path(args.teacher).expanduser()
        if not apath.is_file():
            print(f"missing teacher anchor: {apath}", file=sys.stderr)
            return 2
        anchor_arrays = np.load(apath, allow_pickle=False)
        anchor_meta = json.loads(anchor_arrays["meta"].item())
        if int(anchor_meta.get("chunk", -1)) != args.chunk:
            print(
                f"teacher anchors were built at chunk {anchor_meta.get('chunk')}, "
                f"not {args.chunk}; rebuild them or pass the matching --chunk",
                file=sys.stderr,
            )
            return 2
        print(
            f"teacher anchors: {apath} (chunk {anchor_meta['chunk']}, "
            f"source {anchor_meta.get('model', '?')})",
            file=sys.stderr,
        )

    print(f"loading {args.model} ...", file=sys.stderr, flush=True)
    model, tokenizer = load_omlx_quant(
        args.model, moe_resident_fraction=args.moe_resident_fraction
    )
    if model is None or tokenizer is None:
        print("load returned no model/tokenizer", file=sys.stderr)
        return 1

    close = getattr(model, "close", None)
    try:
        if anchor_meta is not None:
            print(f"{'file':<24} {'tokens':>8} {'NLL/tok':>9} {'PPL':>10} {'bits/tok':>8} "
                  f"{'teachNLL':>9} {'dNLL':>8} {'d%':>7} {'top-1':>6}")
        else:
            print(f"{'file':<28} {'tokens':>10} {'NLL/token':>10} {'PPL':>10} {'bits/tok':>9}")
        total: dict[str, float] = {}
        total_top1: dict[str, float] = {}
        total_delta: dict[str, tuple[float, float]] = {}
        grand_nll = grand_toks = 0
        grand_teacher = grand_agree = 0.0
        save_meta: dict[str, object] = {"model": args.model, "chunk": args.chunk, "files": []}
        saved: dict[str, np.ndarray] = {}
        for path_like in args.files:
            path = Path(path_like)
            sha = file_sha256(path)
            teacher = None
            if anchor_meta is not None:
                idx = next(
                    (i for i, e in enumerate(anchor_meta["files"]) if e["sha256"] == sha),
                    None,
                )
                if idx is None:
                    print(
                        f"no teacher anchor for {path.name} (sha256 {sha[:12]}...); "
                        "the file changed after the anchor was built",
                        file=sys.stderr,
                    )
                    return 2
                teacher = {
                    "targets": anchor_arrays[f"f{idx}_targets"],
                    "argmax": anchor_arrays[f"f{idx}_argmax"],
                    "nll": anchor_arrays[f"f{idx}_nll"],
                }
            nll_sum, scored, extra = score_file(
                model,
                tokenizer,
                path,
                args.chunk,
                teacher=teacher,
                collect=args.teacher_save is not None,
            )
            if not scored:
                continue
            if args.teacher_save is not None:
                i = len(save_meta["files"])
                saved[f"f{i}_targets"] = extra["targets"]
                saved[f"f{i}_argmax"] = extra["argmax"]
                saved[f"f{i}_nll"] = extra["nll"]
                save_meta["files"].append({"name": path.name, "sha256": sha})
            ppl = math.exp(nll_sum / scored)
            mean_nll = nll_sum / scored
            total[path_like] = ppl
            grand_nll += nll_sum
            grand_toks += scored
            if anchor_meta is not None:
                t_mean = extra["teacher_nll"] / scored
                delta = mean_nll - t_mean
                pct = 100.0 * delta / t_mean if t_mean else 0.0
                top1 = extra["agree"] / scored
                grand_teacher += extra["teacher_nll"]
                grand_agree += extra["agree"]
                total_top1[path_like] = top1
                total_delta[path_like] = (delta, pct)
                print(
                    f"{path.name:<24} {scored:>8} {mean_nll:>9.4f} {ppl:>10.4f} "
                    f"{mean_nll / math.log(2):>8.4f} {t_mean:>9.4f} {delta:>+8.4f} "
                    f"{pct:>+7.2f} {top1:>6.3f}"
                )
            else:
                print(f"{path.name:<28} {scored:>10} {mean_nll:>10.4f} {ppl:>10.4f} "
                      f"{mean_nll / math.log(2):>9.4f}")
        if grand_toks:
            pooled = math.exp(grand_nll / grand_toks)
            if anchor_meta is not None:
                t_mean = grand_teacher / grand_toks
                delta = grand_nll / grand_toks - t_mean
                pct = 100.0 * delta / t_mean if t_mean else 0.0
                print(
                    f"{'POOLED':<24} {grand_toks:>8} {grand_nll / grand_toks:>9.4f} {pooled:>10.4f} "
                    f"{(grand_nll / grand_toks) / math.log(2):>8.4f} {t_mean:>9.4f} "
                    f"{delta:>+8.4f} {pct:>+7.2f} {grand_agree / grand_toks:>6.3f}"
                )
            else:
                print(f"{'POOLED':<28} {grand_toks:>10} {grand_nll / grand_toks:>10.4f} {pooled:>10.4f} "
                      f"{(grand_nll / grand_toks) / math.log(2):>9.4f}")
            print(f"\nrun summary: PPL @ {args.model.split('/')[-1]}")
            for k, v in total.items():
                print(f"  {Path(k).name:<28} {v:.4f}")
            print(f"  {'POOLED':<28} {pooled:.4f}")
            if anchor_meta is not None:
                print("\nteacher-anchored vs source:")
                for k, (delta, pct) in total_delta.items():
                    print(f"  {Path(k).name:<28} dNLL {delta:+.4f} ({pct:+.2f}%)  "
                          f"top-1 {total_top1[k]:.4f}")
        if args.teacher_save is not None and saved:
            saved["meta"] = np.array(json.dumps(save_meta))
            out = Path(args.teacher_save).expanduser()
            out.parent.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(out, **saved)
            print(f"\nteacher anchors written: {out} "
                  f"({len(save_meta['files'])} files, chunk {args.chunk})", file=sys.stderr)
        return 0
    finally:
        if close is not None:
            close()


if __name__ == "__main__":
    sys.exit(main())
