#!/usr/bin/env python3
# lint_duplicates.py — duplicate-overlap gate for calibration sources.
#
# Two checks, both over blank-line `---` blank-line blocks:
#   1. Exact duplicate blocks across files (or twice in one file) -> FAILURE.
#      Declared mechanism-home recurrences are intentional near-matches,
#      never byte-identical blocks, so exact duplicates are always a bug
#      (usually a bad append or a mined instance ingested twice).
#   2. Near-duplicate report: top pairs by shared word-8-shingle count.
#      Informational only (warnings) — intentional recurrences from the
#      SPEC mechanism-homes list legitimately share vocabulary.
#
# Usage: python3 scripts/lint_duplicates.py [--top N]
# Exit 1 on any exact duplicate, 0 otherwise.
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CALIB = ROOT / "calibration"
SHINGLE = 8


def blocks_of(path):
    text = path.read_text(encoding="utf-8")
    return [b.strip() for b in re.split(r"\n---\n", text) if b.strip()]


def shingles(block):
    words = re.findall(r"[a-z0-9_]+", block.lower())
    return {tuple(words[i : i + SHINGLE]) for i in range(len(words) - SHINGLE + 1)}


def main():
    top_n = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 10
    files = sorted(CALIB.glob("*.txt"))
    seen = {}
    failures = []
    sigs = {}
    for path in files:
        for i, block in enumerate(blocks_of(path)):
            key = (path.name, i)
            digest = hash(block)
            if digest in seen and seen[digest] != block:
                pass  # hash collision guard below by real comparison
            for other_key, other_block in list(sigs.items()):
                if other_block == block:
                    failures.append(f"exact duplicate: {key[0]}#{key[1]} == {other_key[0]}#{other_key[1]}")
                    break
            sigs[key] = block

    # Near-duplicate pairs by shared shingle count.
    keys = list(sigs)
    pair_scores = []
    for a in range(len(keys)):
        sa = shingles(sigs[keys[a]])
        if not sa:
            continue
        for b in range(a + 1, len(keys)):
            if keys[a][0] == keys[b][0]:
                continue
            shared = len(sa & shingles(sigs[keys[b]]))
            if shared:
                pair_scores.append((shared, keys[a], keys[b]))
    pair_scores.sort(reverse=True)

    print(f"lint_duplicates: {len(files)} files, {len(sigs)} blocks")
    for line in failures:
        print("FAIL", line)
    print(f"top-{top_n} cross-file shingle overlaps (informational):")
    for shared, a, b in pair_scores[:top_n]:
        print(f"warn  shared={shared:4d} {a[0]}#{a[1]} <-> {b[0]}#{b[1]}")
    if failures:
        print(f"lint_duplicates: {len(failures)} exact-duplicate failures")
        return 1
    print("lint_duplicates: 0 exact-duplicate failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
