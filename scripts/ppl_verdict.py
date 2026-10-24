#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Plain-language heldout verdict from ``ppl_heldout.py --json`` results.

Two questions, one card:

* vs source floor — how far is this quant above the checkpoint it came from?
  Paired per-token NLL delta with a 95% CI, plus top-1 agreement.
* vs baseline — did this build lose anything against the last accepted build?
  Paired per-token delta with a 95% CI.

Decision rule: the highest-token file (heldout-se2) has veto power. It
regressing is a REGRESSION; a small-file regression is REVIEW; everything
else is SHIP. PPL is a floor check — coding ability is decided by task evals.

Usage:
    ppl_verdict.py --results ~/oqup/ppl-coder-q8.json
    ppl_verdict.py --results ... --write-baseline      # accept this build
    ppl_verdict.py --results ... --no-history

Baseline promotion is deliberately manual: auto-promoting would turn a
regression into the new normal.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
Z = 1.96


def paired_stats(a: np.ndarray, b: np.ndarray) -> tuple[float, float]:
    """Mean paired difference and its 95% half-width (nats/token)."""
    d = np.asarray(a, dtype=np.float64) - np.asarray(b, dtype=np.float64)
    n = d.size
    if n == 0:
        return 0.0, 0.0
    se = float(d.std(ddof=1)) / math.sqrt(n) if n > 1 else 0.0
    return float(d.mean()), Z * se


def pct(delta: float, base: float) -> float:
    return 100.0 * delta / base if base else 0.0


def classify(delta: float, half: float) -> str:
    """Lower NLL is better."""
    if delta + half < 0:
        return "better"
    if delta - half > 0:
        return "worse"
    return "tie"


def floor_label(delta: float, half: float) -> str:
    if delta - half > 0:
        return "above floor"
    if delta + half < 0:
        return "below floor"
    return "at floor"


def main() -> int:
    ap = argparse.ArgumentParser(description="Heldout verdict card.")
    ap.add_argument("--results", required=True, help="JSON written by ppl_heldout.py --json")
    ap.add_argument("--baseline", default=str(REPO / "eval" / "baseline.json"),
                    help="accepted-build baseline (default: eval/baseline.json)")
    ap.add_argument("--history", default=str(REPO / "eval" / "history.jsonl"),
                    help="append-only run ledger (default: eval/history.jsonl)")
    ap.add_argument("--write-baseline", action="store_true",
                    help="promote these results to the baseline (manual acceptance)")
    ap.add_argument("--no-history", action="store_true", help="do not append to the ledger")
    args = ap.parse_args()

    rpath = Path(args.results).expanduser()
    if not rpath.is_file():
        print(f"missing results: {rpath}", file=sys.stderr)
        return 2
    res = json.loads(rpath.read_text(encoding="utf-8"))
    files = res.get("files") or []
    if not files:
        print("results contain no scored files", file=sys.stderr)
        return 2

    bpath = Path(args.baseline).expanduser()
    baseline = None
    if bpath.is_file():
        baseline = json.loads(bpath.read_text(encoding="utf-8"))
    base_chunk_ok = bool(baseline) and int(baseline.get("chunk", -1)) == int(res["chunk"])

    total_tokens = int(res.get("pooled", {}).get("tokens") or sum(f["tokens"] for f in files))
    teacher = res.get("teacher") or {}
    src_label = teacher.get("source") or "—"

    print(f"=== heldout verdict — {Path(res['model']).name} ===")
    print(f"{res.get('created', '?')} · chunk {res['chunk']} · {total_tokens:,} tokens")
    print(f"source floor: {src_label}")
    if baseline is not None:
        print(f"baseline: {Path(str(baseline.get('model', '?'))).name} "
              f"@ {baseline.get('accepted', '?')} (chunk {baseline.get('chunk')})")

    print()
    print(f"{'file':<20} {'tokens':>7} {'NLL/tok':>8} {'vs source':>18} "
          f"{'top-1':>14} {'vs baseline':>18} {'status':>8}")

    rows: list[dict] = []
    for f in files:
        name = f["name"]
        tokens = int(f["tokens"])
        arr = np.asarray(f["nll_per_token"], dtype=np.float64)
        mean_nll = float(arr.mean())

        src_cell = "—"
        src_floor = "—"
        src_pct = src_ci = None
        if f.get("teacher_nll_per_token"):
            t = np.asarray(f["teacher_nll_per_token"], dtype=np.float64)
            if t.size == arr.size:
                dm, dh = paired_stats(arr, t)
                tmean = float(t.mean())
                src_pct, src_ci = pct(dm, tmean), pct(dh, tmean)
                src_cell = f"{src_pct:+.2f}% ±{src_ci:.2f}%"
                src_floor = floor_label(dm, dh)

        top_cell = "—"
        top1 = f.get("agree", None)
        if top1 is not None and tokens:
            p = float(top1) / tokens
            half = Z * math.sqrt(max(p * (1.0 - p), 0.0) / tokens)
            top_cell = f"{p:.3f} ±{half:.3f}"

        base_cell = "—"
        base_pct = base_ci = None
        status = src_floor
        if baseline is not None and base_chunk_ok:
            bf = (baseline.get("files") or {}).get(name)
            if bf is None:
                base_cell = "n/a (new file)"
                status = "n/a"
            elif bf.get("sha256") != f.get("sha256"):
                base_cell = "n/a (changed)"
                status = "n/a"
            else:
                b = np.asarray(bf["nll"], dtype=np.float64)
                if b.size != arr.size:
                    base_cell = "n/a (length)"
                    status = "n/a"
                else:
                    dm, dh = paired_stats(arr, b)
                    bmean = float(b.mean())
                    base_pct, base_ci = pct(dm, bmean), pct(dh, bmean)
                    base_cell = f"{base_pct:+.2f}% ±{base_ci:.2f}%"
                    status = classify(dm, dh)
        elif baseline is not None:
            base_cell = "n/a (chunk)"
            status = "n/a"

        print(f"{name:<20} {tokens:>7} {mean_nll:>8.4f} {src_cell:>18} "
              f"{top_cell:>14} {base_cell:>18} {status:>8}")
        rows.append({"name": name, "tokens": tokens, "nll": mean_nll,
                     "src_pct": src_pct, "src_ci": src_ci,
                     "base_pct": base_pct, "base_ci": base_ci,
                     "status": status,
                     "top1": (float(top1) / tokens) if (top1 is not None and tokens) else None})

    comparable = [r for r in rows if r["status"] in {"better", "tie", "worse"}]
    if baseline is None:
        verdict = "FIRST RUN — no baseline yet (accept a good build with --write-baseline)"
    elif not base_chunk_ok:
        verdict = (f"BASELINE STALE — baseline chunk {baseline.get('chunk')} vs "
                   f"{res['chunk']}; re-accept a baseline at this chunk")
    elif not comparable:
        verdict = "BASELINE STALE — no comparable files; re-accept the baseline"
    else:
        decisive = max(comparable, key=lambda r: r["tokens"])
        worse = [r for r in comparable if r["status"] == "worse"]
        if decisive["status"] == "worse":
            verdict = (f"REGRESSION — {decisive['name']} is worse than baseline "
                       f"beyond noise; do not accept")
        elif worse:
            verdict = ("REVIEW — " + ", ".join(r["name"] for r in worse) +
                       " worse than baseline; check before accepting")
        else:
            verdict = "SHIP — no register worse than baseline beyond noise"

    print(f"\nbottom line: {verdict}")
    print("(PPL is a floor check; coding ability is decided by task evals.)")

    if args.write_baseline:
        payload = {
            "schema": 1,
            "accepted": res.get("created"),
            "model": res.get("model"),
            "chunk": res.get("chunk"),
            "teacher": res.get("teacher"),
            "files": {
                f["name"]: {
                    "sha256": f.get("sha256"),
                    "tokens": f["tokens"],
                    "nll": f["nll_per_token"],
                    "nll_per_token": float(np.mean(f["nll_per_token"])),
                    "top1": (
                        float(f["agree"]) / f["tokens"]
                        if f.get("agree") is not None else None
                    ),
                    "teacher_nll_per_token": (
                        float(np.mean(f["teacher_nll_per_token"]))
                        if f.get("teacher_nll_per_token") else None
                    ),
                }
                for f in files
            },
        }
        bpath.parent.mkdir(parents=True, exist_ok=True)
        bpath.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
        print(f"baseline updated: {bpath} <- {Path(res['model']).name}")

    if not args.no_history and not args.write_baseline:
        record = {
            "created": res.get("created"),
            "model": res.get("model"),
            "chunk": res.get("chunk"),
            "teacher": src_label,
            "verdict": verdict,
            "files": {
                r["name"]: {
                    "tokens": r["tokens"],
                    "nll_per_token": r["nll"],
                    "top1": r["top1"],
                    "vs_source_pct": r["src_pct"],
                    "vs_source_ci_pct": r["src_ci"],
                    "vs_baseline_pct": r["base_pct"],
                    "vs_baseline_ci_pct": r["base_ci"],
                    "status": r["status"],
                }
                for r in rows
            },
        }
        hpath = Path(args.history).expanduser()
        hpath.parent.mkdir(parents=True, exist_ok=True)
        with hpath.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record) + "\n")
        print(f"history: {hpath} (+1)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
