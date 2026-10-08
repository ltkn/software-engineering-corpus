#!/usr/bin/env python3
"""reasoning_report.py — how much *search* does the corpus show, and where?

A report, not a gate: it always exits 0. It exists because "the corpus teaches
conclusions, not reasoning" is a claim about the bundle, and a claim like that has
to be re-measurable after a pass instead of remembered.

What it counts, per block (marks are matched case-insensitively in the block text):

  killed      a hypothesis named and then killed by an observation
  branch      two or more hypotheses held against each other
  predict     a test chosen because the hypotheses predicted different things
  deadend     a dead end, wrong turn, or near-miss fix named as such
  check       an explicit sanity check before believing the result
  uncertain   stated uncertainty where the evidence stopped short
  ask         a question that had to be asked of a person, not of a measurement

A block is *deep* when it carries three or more distinct marks: one hedged sentence
is decoration, three is a trace. Depth co-located with stack vocabulary is the point —
`--by-band` splits deep blocks between the thinking files and the rest, because
reasoning that only ever appears in 01-05 is learned as a style of that band and lost
in Java and SQL prose at 4 bits.

Usage:
  scripts/reasoning_report.py                  # working tree
  scripts/reasoning_report.py --compare HEAD   # working tree vs a git revision
"""
import argparse
import re
import subprocess
import sys

ROOT = "calibration/"
MARKS = {
    "killed": r"wrong hypothesis|first (?:guess|thought)|what (?:killed it|ended the)|killed (?:it|by)|ruled out|not the (?:bug|cause)",
    "branch": r"second hypothesis|third hypothesis|two hypotheses|either .* or|candidate (?:cause|explanation)|three hypotheses|hypotheses (?:in cost order|were live)",
    "predict": r"predict|discriminat|would (?:show|look|have been)|separat\w* (?:the|these)|distinguish",
    "deadend": r"dead end|wrong turn|wrong fix|bad fix|near-miss|masked|hid the|hid it|made it worse|nearly shipped",
    "check": r"sanity check|before believing|assert|verify the (?:fix|claim)|prove the|reproduces",
    "uncertain": r"unsure|could not tell|stated uncertainty|open question|unknown|no measurement|the evidence stopped|not sure",
    "ask": r"\basked\b|had to be asked|ask (?:the|first|early)|escalat\w+|product decision|named (?:an )?owner rather than",
}
THINKING = {"01", "02", "03", "04", "05"}
LONG_CHARS = 2000  # ~360 est tokens: a trace with a horizon, not a paragraph


def read(path: str, rev: str | None) -> str:
    if rev:
        return subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True,
                              check=True, text=True).stdout
    return open(path, encoding="utf-8").read()


def measure(rev: str | None) -> dict:
    files = sorted(subprocess.run(["git", "ls-tree", "--name-only", f"{rev}:calibration"],
                                  capture_output=True, text=True, check=True).stdout.split()
                   if rev else [p.split("/", 1)[1] for p in subprocess.run(
                       ["git", "ls-files", ROOT], capture_output=True, text=True, check=True).stdout.split()])
    rows = []
    for f in files:
        if not f.endswith(".txt"):
            continue
        blocks = [b.strip() for b in read(ROOT + f, rev).split("\n---\n") if b.strip()]
        deep = sum(1 for b in blocks
                   if sum(1 for rx in MARKS.values() if re.search(rx, b, re.I)) >= 3)
        anym = sum(1 for b in blocks
                   if any(re.search(rx, b, re.I) for rx in MARKS.values()))
        longs = [len(b) for b in blocks if len(b) > LONG_CHARS]
        rows.append({"file": f, "blocks": len(blocks), "any": anym, "deep": deep,
                     "long": len(longs), "longest": max((len(b) for b in blocks), default=0)})
    return {"rows": rows, "files": len(rows)}


def summarize(m: dict) -> dict:
    rows = m["rows"]
    blocks = sum(r["blocks"] for r in rows)
    deep = sum(r["deep"] for r in rows)
    think_deep = sum(r["deep"] for r in rows if r["file"][:2] in THINKING)
    return {"blocks": blocks, "any": sum(r["any"] for r in rows), "deep": deep,
            "deep_pct": deep / blocks * 100 if blocks else 0,
            "think_deep": think_deep, "stack_deep": deep - think_deep,
            "long": sum(r["long"] for r in rows),
            "longest": max((r["longest"] for r in rows), default=0)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compare", metavar="GITREV", help="also measure that revision and diff")
    args = ap.parse_args()

    now = measure(None)
    base = summarize(now)
    print(f"working tree: {base['blocks']} blocks, {base['deep']} deep "
          f"({base['deep_pct']:.1f}%), {base['long']} blocks over {LONG_CHARS} chars, "
          f"longest {base['longest']} chars")
    print(f"deep blocks by band: thinking 01-05 {base['think_deep']}, everywhere else {base['stack_deep']}")
    print()
    print(f"{'file':38s} {'blocks':>6s} {'any':>5s} {'deep':>5s} {'long':>5s} {'longest':>8s}")
    for r in sorted(now["rows"], key=lambda r: -r["deep"]):
        if r["deep"] or r["long"]:
            print(f"{r['file'][:-4]:38s} {r['blocks']:6d} {r['any']:5d} {r['deep']:5d} "
                  f"{r['long']:5d} {r['longest']:8d}")

    if args.compare:
        prev = summarize(measure(args.compare))
        print(f"\nvs {args.compare}:")
        for k, label in [("blocks", "blocks"), ("any", "blocks with any mark"),
                         ("deep", "deep blocks"),
                         ("think_deep", "deep in thinking band"), ("stack_deep", "deep in stack/other"),
                         ("long", "long traces"), ("longest", "longest block chars")]:
            print(f"  {label:24s} {prev[k]:8d} -> {base[k]:8d}  ({base[k] - prev[k]:+d})")
        print(f"  {'deep share':24s} {prev['deep_pct']:7.1f}% -> {base['deep_pct']:5.1f}%")
    print("\nreasoning_report: report only, always exits 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
