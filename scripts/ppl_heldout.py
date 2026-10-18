#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Teacher-forced perplexity on the corpus heldout files, inside the oMLX venv.

Loads the quant through oMLX's own runtime — for qwen4_exp checkpoints
(DeltaNet + QSA + PLE n-gram) there is no mlx-lm model module, so the load
goes through the vendored mlx-vlm registration exactly at the oMLX server
stack (pre-load patches, forced sanitize, mmap PLE). Run it once per model —
one process per quant, the 125B loads don't co-reside:

    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/Qwen3.8-Flash-Next-oQ5e-stock \
        --files eval/heldout-se.txt eval/heldout-general.txt

    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/Qwen3.8-Flash-Next-oQ5e-coder-q8-ngram-mtp \
        --files eval/heldout-se.txt eval/heldout-general.txt

The script needs the quant host's `~/dev/omlx` venv python (it imports
`omlx` and `mlx_vlm`, both pinned there). Only PPL deltas between runs
matter: same chunking for both models, and the first pair should use the
same files. Per-chunk NLL lines let you spot WHICH heldout region diverges,
not just the average. `heldout-se.txt` is the domain-relevant comparison;
`heldout-general.txt` is where stock shouldn't be sacrificed.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

import mlx.core as mx

DEFAULT_CHUNK = 512  # tokens; matches the build's imatrix seq_length


def load_omlx_quant(model_path: str):
    """Load an oQ quant the way the oMLX server does for qwen4_exp.

    The qwen4_exp text arch (GatedDeltaNet + QSA + PLE n-gram) has no
    mlx-lm model module, so mlx-lm's registry raises "Model type qwen4_exp
    not supported". The arch lives vendored inside omlx for mlx-vlm and is
    wired by the for_vlm pre-load dispatcher (the same recipe the build's
    calibration loads use). Forced sanitize is mandatory for MLX-format
    files: mlx-vlm otherwise skips Model.sanitize and the
    `model.language_model.*` weight keys never bind.
    """
    from omlx.engine.vlm import _force_qwen4_exp_sanitize_on_load
    from omlx.oq import _calibration_model_settings
    from omlx.utils.model_loading import (
        maybe_apply_pre_load_patches,
        materialize_lazy_state,
    )

    path = Path(model_path).expanduser()
    if not path.is_dir():
        raise FileNotFoundError(model_path)
    config = json.loads((path / "config.json").read_text())
    settings = _calibration_model_settings(
        config, has_mtp_heads=False, has_mtp_weights=False
    )
    if settings is None:
        raise ValueError(
            "only qwen4_exp checkpoints are wired through this loader; "
            f"config says {config.get('model_type')!r}"
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


def score_file(model, tokenizer, path: Path, chunk: int) -> tuple[float, int]:
    """Return (total_nll, total_scored_tokens) for a text file."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 0.0, 0

    ids = tokenizer.encode(text)
    if chunk < 2:
        chunk = DEFAULT_CHUNK
    nll_sum = 0.0
    scored = 0
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
    return nll_sum, scored


def main() -> int:
    ap = argparse.ArgumentParser(description="Heldout perplexity for an oMLX-loaded quant.")
    ap.add_argument("--model", required=True, help="quant dir (config.json + safetensors) or HF id")
    ap.add_argument("--files", required=True, nargs="+", help="heldout text files to score, one by one")
    ap.add_argument("--chunk", type=int, default=DEFAULT_CHUNK, help="tokens per scoring window (default 512)")
    args = ap.parse_args()

    for f in args.files:
        if not Path(f).is_file():
            print(f"missing file: {f}", file=sys.stderr)
            return 2

    print(f"loading {args.model} ...", file=sys.stderr, flush=True)
    model, tokenizer = load_omlx_quant(args.model)
    if model is None or tokenizer is None:
        print("load returned no model/tokenizer", file=sys.stderr)
        return 1

    print(f"{'file':<28} {'tokens':>10} {'NLL/token':>10} {'PPL':>10} {'bits/tok':>9}")
    total: dict[str, float] = {}
    grand_nll = grand_toks = 0
    for path in args.files:
        nll_sum, scored = score_file(model, tokenizer, Path(path), args.chunk)
        if not scored:
            continue
        ppl = math.exp(nll_sum / scored)
        total[path] = ppl
        grand_nll += nll_sum
        grand_toks += scored
        print(f"{Path(path).name:<28} {scored:>10} {nll_sum / scored:>10.4f} {ppl:>10.4f} "
              f"{(nll_sum / scored) / math.log(2):>9.4f}")
    if grand_toks:
        pooled = math.exp(grand_nll / grand_toks)
        print(f"{'POOLED':<28} {grand_toks:>10} {grand_nll / grand_toks:>10.4f} {pooled:>10.4f} "
              f"{(grand_nll / grand_toks) / math.log(2):>9.4f}")
        print(f"\nrun summary: PPL @ {args.model.split('/')[-1]}")
        for k, v in total.items():
            print(f"  {Path(k).name:<28} {v:.4f}")
        print(f"  {'POOLED':<28} {pooled:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
