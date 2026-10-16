#!/usr/bin/env python3
# make_bundles.py — assemble the oMLX control-arm calibration bundles.
#
# Build-input-only bundles (like vendor/jundot-oqe/): consumed via
# CORPUS_FILE=..., never linted (the lints glob calibration/), never part of
# eval/. The stock arm needs no bundle — it calibrates on oMLX's own
# built-in oqe_code_multilingual corpus.
#
#   bundles/generic.txt      oMLX's generic-domain slices (en, mixed,
#                            bartowski) — deliberately mismatched with the
#                            SE stack (no code, no tool calling). Same
#                            pipeline as the default build, different text.
#                            Note it is also smaller (~165k tok est vs ~647k
#                            for the default bundle); the imatrix still
#                            samples the same 128x512 tokens from it, so
#                            read the C-vs-B delta with that in mind.
#   bundles/vendor-only.txt  just the vendored SE slices (code,
#                            tool_calling, chat, reasoning) — the
#                            vendor-only arm (--vendor-only; duplicates
#                            vendor/jundot-oqe/ content on purpose so the
#                            bundle sha256 is pinned).
#
# Slice data comes from the same oqe_calibration_data.json (Apache-2.0, see
# vendor/jundot-oqe/ATTRIBUTION.md) that vendor_oqe_slices.py reads. Rerun
# to regenerate; the bundle sha256 is re-recorded in <out>/build.json at
# every build, which is what makes an arm reproducible across overwrites.
#
# Usage:
#   python3 scripts/make_bundles.py <omlx>/omlx/oqe_calibration_data.json
#   python3 scripts/make_bundles.py --vendor-only
import hashlib
import json
import sys
from pathlib import Path

GENERIC = ("en", "mixed", "bartowski")
ROOT = Path(__file__).resolve().parent.parent
VENDOR_DIR = ROOT / "vendor" / "jundot-oqe"
OUTDIR = ROOT / "bundles"

USAGE = (
    "usage: make_bundles.py <oqe_calibration_data.json>   # bundles/generic.txt\n"
    "       make_bundles.py --vendor-only                 # bundles/vendor-only.txt"
)


def write_bundle(name, parts):
    OUTDIR.mkdir(parents=True, exist_ok=True)
    body = "\n\n---\n\n".join(parts) + "\n"
    path = OUTDIR / name
    path.write_text(body, encoding="utf-8")
    print(f"{name:18s} parts={len(parts)} chars={len(body):9d} "
          f"(~{len(body) / 5.5 / 1000:.0f}k tok @5.5ch)")
    print(f"  sha256: {hashlib.sha256(path.read_bytes()).hexdigest()}")


def generic(src):
    data = json.loads(Path(src).read_text(encoding="utf-8"))
    parts, total_texts = [], 0
    for key in GENERIC:
        texts = [t for t in data.get(key, []) if t and t.strip()]
        if not texts:
            print(f"WARN: slice {key!r} missing or empty in {src}")
            continue
        parts.append("\n\n---\n\n".join(t.strip() for t in texts))
        total_texts += len(texts)
        print(f"{key:15s} texts={len(texts):5d} "
              f"chars={sum(len(t) for t in texts):9d}")
    print(f"total texts={total_texts}")
    print(f"source sha256: {hashlib.sha256(Path(src).read_bytes()).hexdigest()}")
    write_bundle("generic.txt", parts)


def vendor_only():
    parts = []
    for name in ("code", "tool_calling", "chat", "reasoning"):
        path = VENDOR_DIR / f"{name}.txt"
        if not path.exists():
            print(f"WARN: vendored slice {name}.txt missing — "
                  f"run scripts/vendor_oqe_slices.py first", file=sys.stderr)
            continue
        parts.append(path.read_text(encoding="utf-8").rstrip("\n"))
    write_bundle("vendor-only.txt", parts)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--vendor-only":
        vendor_only()
    elif len(sys.argv) > 1:
        generic(sys.argv[1])
    else:
        print(USAGE, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
