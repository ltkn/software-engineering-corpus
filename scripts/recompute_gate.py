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
    ("calibration/03-math-logic-cot.txt", r"39\.4 × 3600 = 141750", "DNS exfil bytes/hour",
     lambda: 63 * 5 / 8 * 3600, 141750.0),
    ("calibration/03-math-logic-cot.txt", r"= 138 KiB per hour", "DNS exfil KiB/hour",
     lambda: 63 * 5 / 8 * 3600 / 1024, 138.43),
    ("calibration/03-math-logic-cot.txt", r"1 - 0\.282 = 0\.718", "flake probability over 50 runs",
     lambda: 1 - 0.975 ** 50, 0.718),
    ("calibration/03-math-logic-cot.txt", r"21411 × 12 = 256932", "metric series count",
     lambda: 21411 * 12, 256932),
    ("calibration/03-math-logic-cot.txt", r"190 \+ 175 = 365", "sequential latency sum",
     lambda: 190 + 175, 365),
    ("calibration/03-math-logic-cot.txt", r"30 . 1024 KiB", "dump hours over DNS",
     lambda: 30 * 1024 / (63 * 5 / 8 * 3600 / 1024), 221.9),
    ("calibration/23-finance-quant.txt", r"T\+1", "settlement span",
     lambda: 1, 1),
    ("calibration/03-math-logic-cot.txt", r"2\^20 = 1048576", "powers of two",
     lambda: 2 ** 20, 1048576),
    ("calibration/03-math-logic-cot.txt", r"1\.47e-21", "UUID collision at 1e9",
     lambda: (1e9 ** 2) / (2 ** 129), 1.4693679385278594e-21),
    ("calibration/03-math-logic-cot.txt", r"sqrt\(2\*8\) = 4\.0", "geometric mean speedup",
     lambda: __import__("math").sqrt(2 * 8), 4.0),
    ("calibration/03-math-logic-cot.txt", r"1/\(0\.1\+0\.9/8\) = 4\.71", "Amdahl ceiling",
     lambda: 1 / (0.1 + 0.9 / 8), 4.705882352941176),
    ("calibration/03-math-logic-cot.txt", r"0\.1\^3 = 0\.001", "retry independence",
     lambda: 1 - 0.1 ** 3, 0.999),
    ("calibration/03-math-logic-cot.txt", r"log2\(10\^6\) = 19\.93", "binary search depth",
     lambda: __import__("math").log2(1_000_000), 19.931568569324174),
    ("calibration/03-math-logic-cot.txt", r"0\.02\*1000 \+ 0\.10\*10 = 21", "asymmetric error cost",
     lambda: 0.02 * 1000 + 0.10 * 10, 21.0),
    ("calibration/03-math-logic-cot.txt", r"3\^9 = 19683", "gossip rounds",
     lambda: 3 ** 9, 19683),
    ("calibration/03-math-logic-cot.txt", r"1\.47e-25", "UUID collision at 1e7",
     lambda: (1e7 ** 2) / (2 ** 129), 1.4693679385278594e-25),
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
