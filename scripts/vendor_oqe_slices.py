#!/usr/bin/env python3
# vendor_oqe_slices.py — extract upstream oQe calibration slices into vendor/.
#
# Takes ONLY the agentic+coding slices (code, tool_calling, chat, reasoning)
# from omlx's oqe_calibration_data.json (Apache-2.0, see
# vendor/jundot-oqe/ATTRIBUTION.md). Asian-language slices (ko/zh/ja) and
# the general/en/mixed/bartowski slices are deliberately NOT vendored.
#
# Output: vendor/jundot-oqe/<slice>.txt, one upstream text per block using
# the corpus block delimiter. These files are BUILD INPUT ONLY: format and
# budget lints glob calibration/ and never see vendor/. Do not hand-edit
# them; rerun this script to regenerate.
#
# Usage:
#   python3 scripts/vendor_oqe_slices.py <oqe_calibration_data.json>
import hashlib
import json
import sys
from pathlib import Path

SLICES = ("code", "tool_calling", "chat", "reasoning")

ROOT = Path(__file__).resolve().parent.parent
OUTDIR = ROOT / "vendor" / "jundot-oqe"


def main():
    src = Path(sys.argv[1])
    data = json.loads(src.read_text(encoding="utf-8"))
    OUTDIR.mkdir(parents=True, exist_ok=True)
    total_texts, total_chars = 0, 0
    for key in SLICES:
        texts = [t for t in data.get(key, []) if t and t.strip()]
        if not texts:
            print(f"WARN: slice {key!r} missing or empty in {src}")
            continue
        body = "\n\n---\n\n".join(t.strip() for t in texts) + "\n"
        (OUTDIR / f"{key}.txt").write_text(body, encoding="utf-8")
        chars = sum(len(t) for t in texts)
        total_texts += len(texts)
        total_chars += chars
        print(f"{key:15s} texts={len(texts):5d} chars={chars:9d}")
    print(f"total texts={total_texts} chars={total_chars} (~{total_chars/5.5/1000:.0f}k tok @5.5ch)")
    print(f"source sha256: {hashlib.sha256(src.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    sys.exit(main())
