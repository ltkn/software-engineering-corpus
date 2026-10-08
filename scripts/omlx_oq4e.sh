#!/usr/bin/env bash
# omlx_oq4e.sh — redo an oQ4e quant of Qwen3.8-Flash-Next on the oMLX branch.
#
# Runs on the quant machine (M3 Max). Builds the calibration bundle from
# this repo's calibration/*.txt, launches quantize_oq_streaming with the
# custom corpus + Q8 N-gram table, then verifies the report and config.
#
# Nothing in the llama.cpp flow (README, SPEC, manifest, other scripts) is
# involved: this file is additive only.
#
# Usage:
#   scripts/omlx_oq4e.sh <version> [--src <model-snapshot-dir>] [--dry-run]
#
#   <version>   experiment suffix, e.g. se2 (must be new: output is never
#               overwritten; rerun with a new version per corpus iteration)
#
# Env overrides (defaults match the quant machine layout):
#   OMLX_REPO   omlx checkout on the feat/custom-corpus-ngram-q8 branch
#               (default: ~/dev/omlx)
#   VENV_PY     branch venv python (default: $OMLX_REPO/.venv-3.12/bin/python)
#   OQUP        run artifacts: logs + imatrix caches (default: ~/oqup)
#   MODELS_OUT  quant outputs, one subdir per version (default: ~/models-out)
#   NGRAM_BITS  PLE N-gram table width, default 8 (rest follows OQ_LEVEL)
#   OQ_LEVEL    oQ base level, default 4 (oQ4e). scripts/omlx_oq5e.sh sets 5.
#   OQ_SAMPLES  imatrix samples, default 128
#   OQ_SEQLEN   imatrix sequence length, default 512
#
# Examples:
#   scripts/omlx_oq4e.sh se2
#   scripts/omlx_oq4e.sh se3 --src ~/.cache/huggingface/hub/models--Qwen--Qwen3.8-Flash-Next/snapshots/<sha>
#   nohup scripts/omlx_oq4e.sh se2 > ~/oqup/se2-driver.log 2>&1 &
set -euo pipefail

VERSION="${1:?usage: omlx_oq4e.sh <version> [--src <dir>] [--dry-run]}"
shift || true

SRC="${SRC:-}"
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --src) SRC="${2:?--src needs a directory}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

CORPUS_REPO="$(cd "$(dirname "$0")/.." && pwd)"
OMLX_REPO="${OMLX_REPO:-$HOME/dev/omlx}"
VENV_PY="${VENV_PY:-$OMLX_REPO/.venv-3.12/bin/python}"
OQUP="${OQUP:-$HOME/oqup}"
MODELS_OUT="${MODELS_OUT:-$HOME/models-out}"
NGRAM_BITS="${NGRAM_BITS:-8}"
OQ_LEVEL="${OQ_LEVEL:-4}"
OQ_SAMPLES="${OQ_SAMPLES:-128}"
OQ_SEQLEN="${OQ_SEQLEN:-512}"

if [ -z "$SRC" ]; then
    # Default: orcarouter uncensored Flash-Next snapshot (single snapshot dir).
    CANDIDATE="$HOME/.cache/huggingface/hub/models--orcarouter--Qwen3.8-Flash-Next-Uncensored/snapshots"
    if [ -d "$CANDIDATE" ] && [ "$(ls "$CANDIDATE" | wc -l)" -eq 1 ]; then
        SRC="$CANDIDATE/$(ls "$CANDIDATE")"
    else
        echo "cannot infer source model: pass --src <snapshot-dir>" >&2
        exit 2
    fi
fi

BUNDLE="/tmp/calibration-se.txt"
OUT="$MODELS_OUT/Qwen3.8-Flash-Next-Uncensored-oQ${OQ_LEVEL}e-$VERSION"
NPZ="$OQUP/imatrix-$VERSION.npz"
LOG="$OQUP/oq${OQ_LEVEL}e-$VERSION.log"
RUNNER="$OQUP/run_oq${OQ_LEVEL}e_$VERSION.py"

echo "== omlx_oq${OQ_LEVEL}e $VERSION =="
echo "corpus repo : $CORPUS_REPO"
echo "omlx repo   : $OMLX_REPO ($(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'NOT A GIT CHECKOUT'))"
echo "source      : $SRC"
echo "output      : $OUT"
echo "imatrix     : $NPZ"

[ -f "$SRC/config.json" ] || { echo "missing $SRC/config.json" >&2; exit 1; }
[ -f "$VENV_PY" ] || { echo "missing venv python: $VENV_PY" >&2; exit 1; }
if [ -e "$OUT" ]; then
    echo "output already exists: $OUT (use a new <version>, outputs are never overwritten)" >&2
    exit 1
fi
BRANCH="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$BRANCH" != "feat/custom-corpus-ngram-q8" ]; then
    echo "WARNING: omlx repo is on '$BRANCH', expected feat/custom-corpus-ngram-q8" >&2
fi

echo "== building bundle =="
cat "$CORPUS_REPO"/calibration/*.txt > "$BUNDLE"
wc -c "$BUNDLE"

echo "== writing runner $RUNNER =="
mkdir -p "$OQUP" "$MODELS_OUT"
cat > "$RUNNER" <<EOF
from omlx.oq import quantize_oq_streaming
quantize_oq_streaming(
    model_path="$SRC",
    output_path="$OUT",
    oq_level=$OQ_LEVEL, enhanced=True,
    calib_dataset="$BUNDLE",
    sensitivity_calib_dataset="$BUNDLE",
    ngram_bits=$NGRAM_BITS,
    imatrix_cache_path="$NPZ",
    imatrix_reuse_cache=False,
    imatrix_num_samples=$OQ_SAMPLES, imatrix_seq_length=$OQ_SEQLEN,
)
EOF

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: runner written, not launched"
    exit 0
fi

echo "== launching (log: $LOG) =="
"$VENV_PY" "$RUNNER" > "$LOG" 2>&1
echo "== quantize returned, verifying =="
"$VENV_PY" - "$OUT" "$BUNDLE" "$OQ_LEVEL" "$NGRAM_BITS" <<'PY'
import json
import sys

out, bundle, level, ngram_bits = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
report = json.load(open(f"{out}/oq_imatrix_report.json"))
q = json.load(open(f"{out}/config.json"))["quantization"]
ngram = {k: v for k, v in q.items() if "ngram" in k}

print(f"calib_dataset : {report['calib_dataset']}")
print(f"cache_reused  : {report['cache_reused']}")
print(f"imatrix entries: {report['entry_count']}, missing: {len(report['missing'])}, mismatched: {len(report['mismatched'])}")
print(f"global        : bits={q.get('bits')} group_size={q.get('group_size')}")
print(f"ngram shards  : {len(ngram)}, e.g. {next(iter(ngram.values())) if ngram else None}")

ok = (
    report["calib_dataset"] == bundle
    and report["cache_reused"] is False
    and report["entry_count"] > 0
    and q.get("bits") == level
    and ngram
    and all(
        v.get("bits") == ngram_bits and v.get("group_size") == 32
        for v in ngram.values()
    )
)
print("VERIFY:", "OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
PY
echo "== done: $OUT =="
