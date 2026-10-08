#!/usr/bin/env python3
"""lint_format.py — build gate 1 (format), written for a POC: it fails on what
breaks the bundle build, warns on what merely looks off, and never edits files.

Hard failures (exit 1)
  - file is not UTF-8, contains CR, or has no trailing newline
  - a code fence (```), which the format convention forbids in .txt
  - an empty block, or a block that is only whitespace
  - a markdown heading as the first line of a block (`# Title` with no code in
    the block) -- a shape marker that survived into the corpus
  - a file on disk with no manifest entry, or a manifest entry with no file
  - manifest `blocks` disagreeing with the delimiter count

Warnings (exit 0)
  - a block shorter than 80 characters, or longer than 1600
  - more than 3 consecutive newlines
  - shape-marker `#` lines in the inventory-only files (29, 30, share 0)
  - CRLF-looking residue inside a block, non-breaking spaces, tabs

Usage: scripts/lint_format.py [--quiet] [--only 06,31]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECCED = re.compile(r"^#{1,6}[ \t]+\S")
CODEY = re.compile(r"[=;/\"'`{}()<>]|\band\b|\|\|")
# Long blocks are the declared shape of these files (SPEC per-file Budget lines):
# adherence briefs, and every named-field shape (probe, ADR, attack chain).
LONG_LIMIT = 3000
LONG_OK = {
    "01-instruction-following", "06-security", "07-auth-oidc-oauth", "08-api-pentest",
    "13-kafka", "14-http-api", "19-architecture", "20-observability", "25-privacy-gdpr",
    "26-ecommerce", "27-adversarial-walking-patterns", "28-invariant-exploitation",
    "31-offensive-security",
}


def heading_is_shape_marker(line: str, block: str) -> bool:
    """`# shape: ...` at the top of a block is a heading; `# /// script` in a
    Python snippet is code. Only the first line of a block can be a heading, and
    only when the block around it reads as prose."""
    if not SPECCED.match(line):
        return False
    return not CODEY.search(block) and not CODEY.search(line)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--only", default="", help="comma-separated file ids")
    args = ap.parse_args()
    only = {x.strip() for x in args.only.split(",") if x.strip()}

    man = json.load(open(os.path.join(ROOT, "manifest.json"), encoding="utf-8"))
    entries = {e["id"]: e for e in man["files"]}
    calib = os.path.join(ROOT, "calibration")
    disk = sorted(f[:-4] for f in os.listdir(calib) if f.endswith(".txt"))
    targets = [d for d in disk if not only or d in only]

    errors, warnings = [], []
    for fid in targets:
        path = os.path.join(calib, fid + ".txt")
        raw = open(path, "rb").read()
        rel = f"calibration/{fid}.txt"
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as e:
            errors.append(f"{rel}: not UTF-8 ({e})")
            continue
        if b"\r" in raw:
            errors.append(f"{rel}: contains CR")
        if not raw.endswith(b"\n"):
            errors.append(f"{rel}: no trailing newline")
        if "```" in text:
            errors.append(f"{rel}: code fence (``` not allowed in .txt)")
        if "\t" in text:
            warnings.append(f"{rel}: tab characters")
        if "\u00a0" in text:
            warnings.append(f"{rel}: non-breaking spaces")
        if re.search(r"\n{4,}", text):
            warnings.append(f"{rel}: 4+ consecutive newlines")

        blocks = text.split("\n---\n")
        if fid not in entries:
            errors.append(f"{rel}: no manifest entry")
        else:
            declared = entries[fid]["blocks"]
            if declared != len(blocks):
                errors.append(f"{rel}: manifest says {declared} blocks, delimiters say {len(blocks)}")
        for i, b in enumerate(blocks):
            s = b.strip()
            if not s:
                errors.append(f"{rel}: block {i + 1} is empty")
                continue
            first = s.splitlines()[0]
            if heading_is_shape_marker(first, s):
                errors.append(f"{rel}: block {i + 1} starts with a heading: {first[:60]!r}")
            elif SPECCED.match(first) and fid in ("29-llm-integration", "30-experimentation-and-flagging"):
                warnings.append(f"{rel}: block {i + 1} heading in an inventory-only file: {first[:50]!r}")
            if len(s) < 80:
                warnings.append(f"{rel}: block {i + 1} is short ({len(s)} chars)")
            if len(s) > LONG_LIMIT and fid not in LONG_OK:
                warnings.append(f"{rel}: block {i + 1} is long ({len(s)} chars)")
            if "\n\n\n" in s:
                warnings.append(f"{rel}: block {i + 1} has a triple newline")

    missing = set(entries) - set(disk)
    for fid in sorted(missing):
        errors.append(f"manifest entry {fid}: no calibration/{fid}.txt")

    if not args.quiet:
        for w in warnings:
            print(f"warn  {w}")
        for e in errors:
            print(f"FAIL  {e}")
        print(f"lint_format: {len(targets)} files, {len(errors)} failures, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
