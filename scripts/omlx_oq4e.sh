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
#   scripts/omlx_oq4e.sh <org/model> <version> [--src <dir>] [--dry-run]
#   scripts/omlx_oq4e.sh <version> [--src <dir>] [--dry-run]   (legacy form)
#
#   <org/model> huggingface repo pair, resolved to the newest cached snapshot,
#               e.g. Qwen/Qwen3.8-Flash-Next
#   <version>   experiment suffix, e.g. coder-8bit-ngram-mtp (must be new:
#               output is never overwritten; rerun with a new version per
#               corpus iteration). Without <org/model>, the source is
#               auto-discovered (exactly one qwen4_exp match required).
#   [ngram_bits] optional PLE N-gram table width: 2 3 4 5 6 8 (default 8).
#               There is no 16: MLX affine tops out at 8-bit.
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
#   PRESERVE_MTP  keep the native MTP draft head (Lightning MTP), default 1.
#               Set to 0 for MTP-free outputs (reproduces pre-MTP runs).
#   HF_HUB_CACHE  huggingface hub cache for source auto-discovery
#               (default: ~/.cache/huggingface/hub)
#
# Examples:
#   scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-8bit-ngram-mtp 8
#   scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-4bit-ngram 4
#   scripts/omlx_oq4e.sh se2
#   scripts/omlx_oq4e.sh se3 --src ~/.cache/huggingface/hub/models--Qwen--Qwen3.8-Flash-Next/snapshots/<sha>
#   nohup scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-8bit-ngram-mtp > ~/oqup/coder-driver.log 2>&1 &
set -euo pipefail

FIRST="${1:?usage: omlx_oq4e.sh [<org/model>] <version> [--src <dir>] [--dry-run]}"
shift || true
if [[ "$FIRST" == */* ]]; then
    REPO="$FIRST"
    VERSION="${1:?usage: omlx_oq4e.sh <org/model> <version> [ngram_bits] [--src <dir>] [--dry-run]}"
    shift || true
else
    REPO=""
    VERSION="$FIRST"
fi
# Optional third positional: N-gram table bit width (integer).
NGRAM_ARG=""
if [ $# -gt 0 ] && [[ "${1:-}" != --* ]]; then
    NGRAM_ARG="$1"
    shift || true
fi

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
if [ -n "$NGRAM_ARG" ]; then
    NGRAM_BITS="$NGRAM_ARG"
fi
case " 2 3 4 5 6 8 " in
    *" $NGRAM_BITS "*) ;;
    *)
        echo "invalid ngram bits '$NGRAM_BITS' (supported: 2 3 4 5 6 8)" >&2
        echo "MLX affine has no 16-bit width; use preserve_ngram_table for unquantized" >&2
        exit 2
        ;;
esac
OQ_LEVEL="${OQ_LEVEL:-4}"
OQ_SAMPLES="${OQ_SAMPLES:-128}"
OQ_SEQLEN="${OQ_SEQLEN:-512}"
PRESERVE_MTP="${PRESERVE_MTP:-1}"
if [ "$PRESERVE_MTP" = "1" ]; then MTP_PY=True; else MTP_PY=False; fi

HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"

if [ -n "${REPO:-}" ] && [ -z "$SRC" ]; then
    # Resolve an explicit repo pair to its newest cached snapshot.
    CAND="$HUB/models--${REPO//\//--}/snapshots"
    [ -d "$CAND" ] || {
        echo "not in cache: $REPO (looked for $CAND)" >&2
        echo "download it first, or check the exact org/model spelling" >&2
        exit 2
    }
    newest=""
    for snap in "$CAND"/*/; do
        [ -f "$snap/config.json" ] || continue
        if [ -z "$newest" ] || [ "$snap" -nt "$newest" ]; then
            newest="$snap"
        fi
    done
    [ -n "$newest" ] || { echo "no snapshots with config.json under $CAND" >&2; exit 2; }
    SRC="${newest%/}"
    if ! grep -q 'qwen4_exp' "$SRC/config.json"; then
        echo "WARNING: $REPO config does not mention qwen4_exp — continuing," >&2
        echo "but the Q8 N-gram override only applies to that family" >&2
    fi
fi

if [ -z "$SRC" ]; then
    # Auto-discover: newest snapshot of every cached model whose config
    # selects the qwen4_exp (Flash-Next) family — official Qwen release,
    # uncensored forks, whatever the cache holds. Exactly one match is
    # used silently; zero or several require an explicit repo or --src.
    MATCHES=""
    for model_dir in "$HUB"/models--*; do
        [ -d "$model_dir/snapshots" ] || continue
        newest=""
        for snap in "$model_dir"/snapshots/*/; do
            [ -f "$snap/config.json" ] || continue
            grep -q 'qwen4_exp' "$snap/config.json" || continue
            if [ -z "$newest" ] || [ "$snap" -nt "$newest" ]; then
                newest="$snap"
            fi
        done
        if [ -n "$newest" ]; then
            MATCHES="$MATCHES${MATCHES:+$'\n'}$newest"
        fi
    done
    NMATCHES=0
    [ -n "$MATCHES" ] && NMATCHES=$(printf '%s\n' "$MATCHES" | wc -l)
    if [ "$NMATCHES" -eq 1 ]; then
        SRC="${MATCHES%/}"
    else
        echo "cannot infer source model ($NMATCHES qwen4_exp candidates):" >&2
        printf '%s\n' "$MATCHES" >&2
        echo "pass --src <snapshot-dir>" >&2
        exit 2
    fi
fi

# Output tag derived from the source: repo pair -> Name, models--Org--Name
# path -> Name, so official and fork quants never share an output directory.
if [ -n "${REPO:-}" ]; then
    MODEL_TAG="${REPO##*/}"
else
    case "$SRC" in
        *models--*)
            _tag="${SRC%%/snapshots/*}"
            _tag="${_tag##*models--}"
            MODEL_TAG="${_tag#*--}"
            ;;
        *) MODEL_TAG="custom-model" ;;
    esac
fi

BUNDLE="/tmp/calibration-se.txt"
OUT="$MODELS_OUT/$MODEL_TAG-oQ${OQ_LEVEL}e-$VERSION"
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
    preserve_mtp=$MTP_PY,
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
