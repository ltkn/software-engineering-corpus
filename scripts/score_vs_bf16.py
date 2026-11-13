#!/usr/bin/env python3
"""score_vs_bf16.py — M3: score quants against the original BF16 model.

Run with the oMLX venv python (needs omlx feat/oqt).

  reference  Stream the BF16 source once over the evaluation files and store
             its top-k next-token probabilities and per-layer expert choices.
             The source never has to fit in memory. Build once, reuse.
  score      Load a quant and compare it with the reference: KL divergence,
             top-1 agreement, routing flips per MoE layer, per slice.
  compare    Print several score files side by side.

  python score_vs_bf16.py reference --src <bf16 dir> --files eval/heldout-written-se.txt <run>/heldout/heldout-oqt-*.txt --out ref.npz
  python score_vs_bf16.py score --model <quant dir> --reference ref.npz --json out.json
  python score_vs_bf16.py compare out1.json out2.json ...
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def build_windows(tokenizer, files: list[str], seq: int, max_windows: int):
    """Each evaluation file becomes its own slice of non-overlapping windows."""
    import mlx.core as mx

    rows, slices = [], []
    for f in files:
        ids = tokenizer.encode(Path(f).read_text(encoding="utf-8"))
        ids = getattr(ids, "input_ids", ids)
        ids = list(ids)
        name = Path(f).stem
        n = min(len(ids) // seq, max_windows)
        for w in range(n):
            rows.append(ids[w * seq:(w + 1) * seq])
            slices.append(name)
        print(f"{name}: {len(ids):,} tokens -> {n} windows of {seq}", flush=True)
    if not rows:
        raise SystemExit("no complete windows: evaluation files are shorter than --seq")
    return mx.array(rows, dtype=mx.int32), slices


def cmd_reference(args) -> int:
    from mlx_lm.tokenizer_utils import load as load_tokenizer
    from omlx import oqt

    src = Path(args.src).expanduser()
    config = json.loads((src / "config.json").read_text())
    windows, slices = build_windows(load_tokenizer(src), args.files, args.seq, args.max_windows)
    t0 = time.time()
    total = int((config.get("text_config") or config).get("num_hidden_layers") or 0)
    meta = oqt.record_reference(
        str(src), config, windows, args.out, slices=slices, top_k=args.top_k,
        progress=lambda li: print(f"reference: layer {li + 1}/{total or '?'} "
                                  f"({time.time() - t0:.0f}s)", flush=True))
    print(f"reference: {meta['windows']} windows x {meta['seq_len']} tokens, top-{meta['top_k']}, "
          f"{len(meta['moe_layers'])} MoE layers -> {args.out} ({(time.time() - t0) / 60:.1f} min)")
    return 0


def cmd_score(args) -> int:
    sys.path.insert(0, str(HERE))
    from ppl_heldout import load_omlx_quant
    from omlx import oqt

    path = Path(args.model).expanduser()
    cfg = json.loads((path / "config.json").read_text())
    if cfg.get("model_type") == "qwen4_exp" and not (path / "model.safetensors.index.json").exists():
        # Single-file outputs have no shard index for the disk-backed n-gram
        # table; load it resident instead (it is small in that case).
        from mlx_vlm.utils import load_model
        from omlx.patches.mlx_vlm_qwen4_exp_compat import configure_qwen4_exp_runtime
        configure_qwen4_exp_runtime(path, mode="resident", mtp_enabled=False)
        model = load_model(path, lazy=True, strict=True)
    else:
        model, _ = load_omlx_quant(args.model)
    t0 = time.time()
    res = oqt.score_against_reference(model, args.reference)
    res["model"] = str(Path(args.model).expanduser())
    res["seconds"] = round(time.time() - t0, 1)
    if args.json:
        Path(args.json).expanduser().write_text(json.dumps(res, indent=1))
    print_table([res])
    worst = sorted(res["routing_by_layer"].items(), key=lambda kv: -kv[1]["mass_shift"])[:5]
    if worst:
        print("routing shift, worst layers: " + ", ".join(
            f"{k}: {v['mass_shift']:.3f} ({v['flip_rate']:.0%} tokens)" for k, v in worst))
    return 0


def print_table(results: list[dict]) -> None:
    slices = sorted({s for r in results for s in r["slices"]})
    head = f"{'quant':40s} {'KL':>8s} {'top-1':>7s} {'route':>7s} {'flips':>6s}"
    head += "".join(f" {('KL ' + s.replace('heldout-', ''))[:12]:>12s}" for s in slices)
    print(head)
    for r in results:
        o = r["overall"]
        line = (f"{Path(r['model']).name[:40]:40s} {o['kl']:8.4f} {o['top1']:7.1%} "
                f"{o.get('routing_mass_shift', 0):7.3f} {o.get('routing_flip_rate', 0):6.1%}")
        line += "".join(f" {r['slices'][s]['kl']:12.4f}" if s in r["slices"] else f" {'-':>12s}" for s in slices)
        print(line)
    print("KL: divergence from the original model (lower is better). top-1: same most likely token. "
          "route: router probability moved to other experts. flips: tokens whose expert set changed.")


def cmd_compare(args) -> int:
    results = [json.loads(Path(f).expanduser().read_text()) for f in args.files]
    refs = {r["reference"]["source"] + str(r["reference"]["windows"]) for r in results}
    if len(refs) > 1:
        print("WARNING: these scores use different references; compare only like with like",
              file=sys.stderr)
    print_table(sorted(results, key=lambda r: r["overall"]["kl"]))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("reference")
    r.add_argument("--src", required=True)
    r.add_argument("--files", nargs="+", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--seq", type=int, default=2048)
    r.add_argument("--max-windows", type=int, default=64, help="per evaluation file")
    r.add_argument("--top-k", type=int, default=64)
    s = sub.add_parser("score")
    s.add_argument("--model", required=True)
    s.add_argument("--reference", required=True)
    s.add_argument("--json")
    c = sub.add_parser("compare")
    c.add_argument("files", nargs="+")
    args = ap.parse_args(argv)
    return {"reference": cmd_reference, "score": cmd_score, "compare": cmd_compare}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
