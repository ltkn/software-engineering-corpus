#!/usr/bin/env python3
"""diversity_report.py — a measurement, not a gate (exit 0 always).

Answers one question per file: is the extra length saying more distinct things,
or the same things again? Repetition matters here specifically because imatrix
calibration over-weights whatever n-grams it sees often, so a file that repeats
its own phrasing spends weight on duplication rather than on coverage.

Per file it reports:
  vocab      distinct content words (lowercased, stop-words and code ids out)
  ids        distinct code-shaped identifiers (camelCase, snake_case, dotted names)
  selfdup    mean share of a block's 6-grams that also appear in another block
             of the same file -- the internal repetition rate
  maxother   largest 6-gram jaccard overlap with any single other file
  top        the most repeated multi-word phrase inside the file

Thresholds used in the prose reading only: selfdup above ~0.12 or top appearing
in many blocks is where a file is repeating itself rather than diversifying.

Usage: scripts/diversity_report.py [--n 6] [--top 8]
"""
import argparse
import collections
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STOP = set("""a an and are as at be been but by for from had has have he her his if in into is it its no not of on or our so that the their them then there these they this to too was we were which while who will with you your can could may might must should would will than too very just also then thus hence however therefore moreover furthermore overall instead rather usually often never always first next last best good bad new old sure true false using use used uses when where what""".split())
WORD = re.compile(r"[A-Za-z][A-Za-z'’-]{2,}")
IDENT = re.compile(r"\b(?:[A-Za-z_][A-Za-z0-9_]*[_.][A-Za-z0-9_.]+|[a-z]+[A-Z][A-Za-z0-9]*|[a-z]+_[a-z0-9_]+|[A-Z][A-Za-z0-9]{2,})\b")


def grams(text, n):
    words = [w.lower() for w in WORD.findall(text)]
    return {tuple(words[i:i + n]) for i in range(max(0, len(words) - n + 1))}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6)
    ap.add_argument("--top", type=int, default=8)
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(ROOT, "calibration", "*.txt")))
    data, sets, union, allv = {}, {}, {}, {}
    for f in files:
        text = open(f, encoding="utf-8").read()
        blocks = [b.strip() for b in text.split("\n---\n") if b.strip()]
        data[f] = blocks
        sets[f] = [grams(b, args.n) for b in blocks]
        union[f] = set().union(*sets[f]) if sets[f] else set()

    print(f"{'file':38s} {'blocks':>6s} {'vocab':>7s} {'ids':>6s} {'selfdup':>8s} {'maxother':>8s}  with")
    for f in files:
        fid = os.path.basename(f)[:-4]
        blocks, gs = data[f], sets[f]
        allg = union[f]
        allv[f] = allg
        selfdup = 0.0
        for i, g in enumerate(gs):
            other = set().union(*[x for j, x in enumerate(gs) if j != i]) if len(gs) > 1 else set()
            selfdup += len(g & other) / len(g) if g else 0.0
        selfdup /= max(1, len(gs))
        words = [w.lower() for w in WORD.findall("\n".join(blocks)) if w.lower() not in STOP]
        vocab = len(set(words))
        ids = len({m.group(0) for b in blocks for m in IDENT.finditer(b)})
        best, bestother = 0.0, ""
        for g2 in sets:
            if g2 == f or not allg or not union[g2]:
                continue
            j = len(allg & union[g2]) / len(allg | union[g2])
            if j > best:
                best, bestother = j, os.path.basename(g2)[:-4]
        print(f"{fid:38s} {len(blocks):6d} {vocab:7d} {ids:6d} {selfdup:8.3f} {best:8.4f}  {bestother}")

    print("\nmost repeated phrases per file (phrase, blocks containing it / total)")
    for f in files:
        blocks = data[f]
        cnt = collections.Counter()
        for b in blocks:
            for g in grams(b, args.n):
                cnt[g] += 1
        top = [(g, c) for g, c in cnt.most_common(args.top) if c > 1]
        fid = os.path.basename(f)[:-4]
        if top:
            g, c = top[0]
            print(f"  {fid:38s} {c}/{len(blocks)}  {' '.join(g)}")
        else:
            print(f"  {fid:38s} — no {args.n}-gram repeats")
    return 0


if __name__ == "__main__":
    sys.exit(main())
