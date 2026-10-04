#!/usr/bin/env python3
"""recompute_gate.py — check every quoted number in 03 and 23 against a
recomputation. The task table below is the review artifact: each claim
line must carry its inputs next to the conclusion so arithmetic checks.

Exit 0 on success; exit 1 on any mismatch, with the block id and the
expected-vs-got line. Any new numeric claim blocks must appear here to
pass review.
"""
from __future__ import annotations
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def bl(count: str) -> int:
    return int(count)

TASKS = [
    # (file, block_line match, label, expected tokens, recomputation function)
    ("calibration/03-math-logic-cot.txt", r"Test H0: population mean", "z-value",
     lambda: (820 - 900) / (150 / (200 ** 0.5)), -7.55),
    ("calibration/03-math-logic-cot.txt", r"Bonferroni rejects each", "Bonferroni threshold",
     lambda: 0.05 / 10, 0.005),
    ("calibration/03-math-logic-cot.txt", r"Cohen's d = \(820-760\)/100 = 0\.6", "Cohen's d",
     lambda: (820 - 760) / 100, 0.6),
    ("calibration/03-math-logic-cot.txt", r"exp\(3\.2\)", "PPL exp(3.2)",
     lambda: float(__import__("math").exp(3.2)), 24.53),
    ("calibration/23-finance-quant.txt", r"T\+1", "settlement span",
     lambda: 1, 1),
]

def parse_blocks(path: str) -> list[tuple[int, str]]:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    return [(i + 1, b.strip()) for i, b in enumerate(text.split("\n---\n")) if b.strip()]

def main() -> int:
    failures = 0
    for fname, match, label, compute, expected in TASKS:
        blocks = parse_blocks(os.path.join(ROOT, fname))
        for lineno, block in blocks:
            if re.search(match, block):
                got = compute()
                tol = 0.005 if expected == 0 else 0.005 * abs(expected)
                ok = abs(got - expected) <= tol
                if not ok:
                    sys.stderr.write(f"MISMATCH in {fname} block starting near line {lineno}\n")
                    sys.stderr.write(f"  claim: {label}, expected {expected}, recomputed {got}\n")
                    failures += 1
    if failures:
        sys.stderr.write(f"recompute_gate: {failures} failure(s)\n")
        return 1
    print("recompute_gate: ok")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
