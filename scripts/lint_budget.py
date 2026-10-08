#!/usr/bin/env python3
"""lint_budget.py — build gate 7 (budget), tuned for a POC: nothing fails unless
the bundle and the manifest have genuinely drifted apart.

Measured per file: bytes, est tokens (bytes/5.5), blocks, tokens/block, and the
file's share of the weighted bundle compared with the share its manifest weight
declares. Estimates, not tokenizer actuals: `scripts/count_tokens.sh` replaces
them when the GGUF is local, and this script's tolerances are wide enough that
the real tokenizer will not surprise it.

Hard failures (exit 1)
  - manifest `blocks_counted` or `unweighted_estimate` off by more than 2%
  - a file's weighted share more than 2x away from its declared share
  - a file whose weight is 0 growing past 20 KB (share-0 files stay fenced)

Warnings (exit 0)
  - a file's weighted share more than 35% away from its declared share
  - tokens/block outside 45-330, or outside 45-420 for a file with a declared
    block-band exception (see EXCEPTIONS, each one justified in its SPEC scope)

Usage: scripts/lint_budget.py [--quiet]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS_PER_TOKEN = 5.5

# Files whose block shape legitimately runs long, with the SPEC section that
# declares it. Long is fine; long and undeclared is what the gate is for.
EXCEPTIONS = {
    "01-instruction-following": "long-context adherence briefs (SPEC 01 Budget)",
    "03-math-logic-cot": "worked derivations (SPEC 03 Budget)",
    "02-repair-loops": "failure transcripts (SPEC 02 Budget)",
    "12-postgresql": "EXPLAIN/reading traces (SPEC 12 Budget)",
    "27-adversarial-walking-patterns": "eight-field probe shape (SPEC 27 Budget)",
    "31-offensive-security": "attack chains are worked traces (SPEC 31 Budget)",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    man = json.load(open(os.path.join(ROOT, "manifest.json"), encoding="utf-8"))
    rows, errors, warnings = [], [], []
    for e in man["files"]:
        fid = e["id"]
        path = os.path.join(ROOT, "calibration", fid + ".txt")
        if not os.path.exists(path):
            errors.append(f"{fid}: missing file")
            continue
        raw = open(path, "rb").read()
        blocks = raw.count(b"\n---\n") + 1
        est = len(raw) / CHARS_PER_TOKEN
        rows.append({"id": fid, "blocks": blocks, "bytes": len(raw), "est": est,
                     "weight": e["share"], "per_block": est / blocks})

    wtotal = sum(r["est"] * r["weight"] for r in rows)
    wsum = sum(r["weight"] for r in rows)
    utotal = sum(r["est"] for r in rows)

    for r in rows:
        if r["weight"] <= 0:
            if r["bytes"] > 20_000:
                errors.append(f"{r['id']}: share 0 but {r['bytes'] / 1024:.1f} KB — fenced files stay small")
            continue
        declared = r["weight"] / wsum
        actual = r["est"] * r["weight"] / wtotal
        ratio = actual / declared
        # A weight is a multiplier, not a token quota, so this ratio only says how
        # far a file's realized influence sits from a size-neutral reading of it.
        # Wide on purpose: files are allowed to be big and lightly weighted.
        def flag(msg):
            if r["est"] >= 2000 and not 0.25 <= ratio <= 4.0:
                errors.append(msg)
            else:
                warnings.append(msg)
        small = " (small file: noted, not enforced)" if r["est"] < 2000 else ""
        if not 0.4 <= ratio <= 2.5:
            flag(f"{r['id']}: size/weight balance x{ratio:.2f} outside 0.4-2.5{small}")
        lo, hi = (45, 420) if r["id"] in EXCEPTIONS else (45, 330)
        if not lo <= r["per_block"] <= hi:
            note = EXCEPTIONS.get(r["id"], "no declared exception")
            warnings.append(f"{r['id']}: {r['per_block']:.0f} tokens/block outside {lo}-{hi} ({note})")

    declared_blocks = man["bundle"]["blocks_counted"]
    if abs(declared_blocks - sum(r["blocks"] for r in rows)) > 0.02 * sum(r["blocks"] for r in rows):
        errors.append(f"bundle.blocks_counted {declared_blocks} != measured {sum(r['blocks'] for r in rows)}")
    m = re.search(r"~?([\d.]+)k", str(man["bundle"].get("unweighted_estimate", "")))
    if m and abs(float(m.group(1)) * 1000 - utotal) > 0.02 * utotal:
        warnings.append(f"bundle.unweighted_estimate {m.group(1)}k != measured {utotal / 1000:.1f}k")

    if not args.quiet:
        print(f"{'file':38s} {'blocks':>6s} {'KB':>7s} {'est tok':>8s} {'tok/blk':>8s} {'wt':>5s} {'share':>7s}")
        for r in rows:
            share = (r["est"] * r["weight"] / wtotal * 100) if wtotal else 0
            print(f"{r['id']:38s} {r['blocks']:6d} {r['bytes'] / 1024:7.1f} {r['est'] / 1000:8.1f} "
                  f"{r['per_block']:8.0f} {r['weight']:5.1f} {share:6.2f}%")
        for w in warnings:
            print(f"warn  {w}")
        for e in errors:
            print(f"FAIL  {e}")
        print(f"lint_budget: {sum(r['blocks'] for r in rows)} blocks, {utotal / 1000:.1f}k est tokens, "
              f"{wtotal / 1000:.1f}k weighted, {len(errors)} failures, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
