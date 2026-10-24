#!/usr/bin/env bash
# omlx_deepseek_v41_oq4e.sh — DeepSeek V4.1 Flash-1017 oQ4e with this corpus.
#
# Builds an oQ4e export from the ORIGINAL DeepSeek V4.1 checkpoint, using
# calibration/*.txt as both the imatrix corpus and the sensitivity corpus.
# Engram defaults to an 8-bit affine table; PRESERVE_NGRAM_TABLE=1 keeps the
# official FP8 tables byte-for-byte instead. scripts/omlx_deepseek_v41_oq25e.sh
# and ..._oq3e.sh are thin wrappers around this file.
#
# DeepSeek V4.1 is not Qwen4-Exp: the source must be the original checkpoint
# (not an oMLX-converted or MLX-quantized copy), Engram widths are
# 2/3/4/6/8, and the report lives in quantization_report.json under
# config.json's omlx_deepseek_v41 section. oQ2.5/oQ3 calibrate one decoder
# block at a time from the source shards by default, so the ~307 GB
# non-Engram source is never resident. oQ4 keeps the source FP4/FP8
# projection precision and does no imatrix/sensitivity work at all.
#
# Control arms (same philosophy as omlx_oq4e.sh):
#   Arm A — stock baseline: <model>-oQ<level>e-stock, oMLX's default
#           calibration corpus + default Engram width, no custom corpus.
#           Auto-building it is OFF by default here because a V4.1 output is
#           hundreds of GB; set OQ_SKIP_STOCK=0 to build/reuse it.
#   Arm B — generic text through the same pipeline:
#           CORPUS_FILE=bundles/generic.txt ... arm-b-generic
#           (bundle built once by scripts/make_bundles.py). C-vs-B isolates
#           the corpus text.
#
# Output policy: same-name <version> reruns overwrite in place (previous log
# moves to *.log.prev; <out>/build.json records the source snapshot, bundle
# sha256, corpus + oMLX commits, Engram width and imatrix settings).
# 'stock' is reserved and arm-* versions refuse overwrite. A pidfile in
# $OQUP refuses concurrent runs of the same version.
#
# After a completed build the heldout PPL runs automatically via
# scripts/ppl_heldout.py. Keep the oMLX server stopped while scoring:
#    OQ_SKIP_PPL=1 ...                 skip scoring
#    PPL_CHUNK=2048 ...                scoring window (default 2048)
#    PPL_FILES="heldout-se2.txt ..."   files relative to eval/
#    OQ_PPL_EXPERT_FRACTION=0.25 ...   routed-expert resident fraction during
#                                      PPL (default 0.25; V4.1 only)
#
# Usage:
#   scripts/omlx_deepseek_v41_oq4e.sh <org/model> <version> [ngram_bits] [--src <dir>] [--dry-run]
#   scripts/omlx_deepseek_v41_oq4e.sh <version> [--src <dir>] [--dry-run]
#
#   <org/model> huggingface repo pair, resolved to the newest cached original
#               snapshot, e.g. deepseek-ai/DeepSeek-V4.1-Flash-1017
#   <version>   experiment suffix, e.g. se-coder-q4-ngram8-mtp.
#   [ngram_bits] Engram table width: 2 3 4 6 8 (default 8). There is no 5.
#               Ignored when PRESERVE_NGRAM_TABLE=1.
#
# Env overrides:
#   OMLX_REPO   omlx checkout on feat/custom-corpus-ngram-q8
#               (default: ~/dev/omlx)
#   VENV_PY     branch venv python (default: $OMLX_REPO/.venv-3.12/bin/python)
#   OQUP        logs + imatrix caches (default: ~/oqup)
#   MODELS_OUT  quant outputs, one subdir per version (default: ~/models-out)
#   NGRAM_BITS  Engram width, default 8
#   PRESERVE_NGRAM_TABLE  set 1 to copy the official FP8 Engram tables
#               unchanged (lossless, ~same size as 8-bit affine) instead of
#               re-quantizing them. Preferred for DeepSeek V4.1; conflicts
#               with the ngram_bits positional.
#   OQ_LEVEL    oQ base level, default 4. Wrappers set 2.5 / 3.
#   OQ_SAMPLES  imatrix samples, default 99999 (every calibration window)
#   OQ_SEQLEN   imatrix sequence length, default 2048
#   STREAM_CALIBRATION  auto (default, streamed), 1, or 0 (resident; needs
#               roughly the full non-Engram source in RAM)
#   PRESERVE_MTP  keep the DSpark draft head, default 1
#   HF_HUB_CACHE  huggingface hub cache (default: ~/.cache/huggingface/hub)
#   VENDOR_SLICES comma-separated upstream slices to append
#               (default: code,tool_calling,chat,reasoning). Empty skips.
#   CORPUS_FILE path to a prebuilt calibration bundle; replaces the assembled
#               bundle entirely, so VENDOR_SLICES is ignored.
#   OQ_SKIP_STOCK default 1 for DeepSeek. Set 0 to ensure the stock baseline.
#   OQ_SKIP_PPL  set to 1 to skip post-build heldout PPL.
#   PPL_FILES / PPL_CHUNK / OQ_PPL_EXPERT_FRACTION  see above.
#
# Examples:
#   scripts/omlx_deepseek_v41_oq25e.sh deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q25-ngram8 8
#   scripts/omlx_deepseek_v41_oq3e.sh  deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q3-ngram8 8
#   scripts/omlx_deepseek_v41_oq4e.sh  deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q4-ngram8 8
#   OQ_SKIP_STOCK=0 scripts/omlx_deepseek_v41_oq3e.sh se-q3-stock-control
#   nohup scripts/omlx_deepseek_v41_oq25e.sh deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q25 8 \
#       > ~/oqup/deepseek-q25-driver.log 2>&1 &
set -euo pipefail

FIRST="${1:?usage: omlx_deepseek_v41_oq4e.sh [<org/model>] <version> [ngram_bits] [--src <dir>] [--dry-run]}"
shift || true
if [[ "$FIRST" == */* ]]; then
    REPO="$FIRST"
    VERSION="${1:?usage: omlx_deepseek_v41_oq4e.sh <org/model> <version> [ngram_bits] [--src <dir>] [--dry-run]}"
    shift || true
else
    REPO=""
    VERSION="$FIRST"
fi

case "$VERSION" in
    stock)
        echo "'stock' is reserved: OQ_SKIP_STOCK=0 ensures the stock baseline automatically" >&2
        echo "(<model>-oQ<level>e-stock). Run your own <version> name as usual." >&2
        exit 2
        ;;
    *[!A-Za-z0-9._-]*|.*)
        echo "invalid version '$VERSION' (use letters, digits, dot, underscore, dash)" >&2
        exit 2
        ;;
esac

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
case " 2 3 4 6 8 " in
    *" $NGRAM_BITS "*) ;;
    *)
        echo "invalid Engram bits '$NGRAM_BITS' (DeepSeek V4.1 supports 2 3 4 6 8; no 5)" >&2
        exit 2
        ;;
esac
OQ_LEVEL="${OQ_LEVEL:-4}"
case " 2.5 3 4 " in
    *" $OQ_LEVEL "*) ;;
    *)
        echo "invalid oQ level '$OQ_LEVEL' (DeepSeek V4.1 scripts support 2.5, 3, 4)" >&2
        exit 2
        ;;
esac
# V4.1 streams calibration by default. Leaving the kwarg out selects the
# library's auto rule (streamed); explicit values support the resident path
# and controlled comparisons.
STREAM_MODE="${STREAM_CALIBRATION:-auto}"
case "$STREAM_MODE" in
    auto) STREAM_LABEL="auto"; STREAM_LINE="" ;;
    1|true) STREAM_LABEL="true"; STREAM_LINE="    stream_calibration=True," ;;
    0|false)
        STREAM_LABEL="false"
        if [ "$OQ_LEVEL" != "4" ]; then
            echo "warning: STREAM_CALIBRATION=0 loads the full non-Engram source; expect ~307 GB" >&2
        fi
        STREAM_LINE="    stream_calibration=False,"
        ;;
    *)
        echo "invalid STREAM_CALIBRATION '$STREAM_MODE' (use auto, 1, or 0)" >&2
        exit 2
        ;;
esac
OQ_SAMPLES="${OQ_SAMPLES:-99999}"
OQ_SEQLEN="${OQ_SEQLEN:-2048}"
PRESERVE_MTP="${PRESERVE_MTP:-1}"
if [ "$PRESERVE_MTP" = "1" ]; then MTP_PY=True; else MTP_PY=False; fi
PRESERVE_NGRAM="${PRESERVE_NGRAM_TABLE:-0}"
if [ "$PRESERVE_NGRAM" = "1" ]; then
    if [ -n "$NGRAM_ARG" ]; then
        echo "PRESERVE_NGRAM_TABLE=1 conflicts with the ngram_bits positional" >&2
        exit 2
    fi
    NGRAM_LINE="    preserve_ngram_table=True,"
    NGRAM_VERIFY="preserved"
    NGRAM_LABEL="preserved"
else
    NGRAM_LINE="    ngram_bits=$NGRAM_BITS,"
    NGRAM_VERIFY="quantized:$NGRAM_BITS"
    NGRAM_LABEL="$NGRAM_BITS"
fi
VENDOR_SLICES_EXPLICIT=0
if [ -n "${VENDOR_SLICES+x}" ]; then VENDOR_SLICES_EXPLICIT=1; fi
VENDOR_SLICES="${VENDOR_SLICES-code,tool_calling,chat,reasoning}"
CORPUS_FILE="${CORPUS_FILE:-}"
if [ -n "$CORPUS_FILE" ]; then
    case "$CORPUS_FILE" in
        /*) ;;
        *) CORPUS_FILE="$CORPUS_REPO/$CORPUS_FILE" ;;
    esac
    if [ "$VENDOR_SLICES_EXPLICIT" = "1" ]; then
        echo "note: CORPUS_FILE replaces bundle assembly; VENDOR_SLICES is ignored" >&2
    fi
fi

HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"

is_original_source() { # <snapshot-dir>
    local dir="$1"
    [ -f "$dir/config.json" ] || return 1
    [ -f "$dir/model.safetensors.index.json" ] || return 1
    grep -q '"model_type"[[:space:]]*:[[:space:]]*"deepseek_v41"' "$dir/config.json" || return 1
    ! grep -q '"omlx_deepseek_v41"' "$dir/config.json" || return 1
    return 0
}

newest_snapshot() { # <models--dir>; prints newest snapshot with config.json
    local root="$1" newest="" snap
    [ -d "$root/snapshots" ] || return 0
    for snap in "$root"/snapshots/*/; do
        [ -f "$snap/config.json" ] || continue
        if [ -z "$newest" ] || [ "$snap" -nt "$newest" ]; then
            newest="$snap"
        fi
    done
    [ -n "$newest" ] && printf '%s\n' "${newest%/}"
}

newest_original_snapshot() { # <models--dir>; newest snapshot passing is_original_source
    local root="$1" newest="" snap
    [ -d "$root/snapshots" ] || return 0
    for snap in "$root"/snapshots/*/; do
        is_original_source "$snap" || continue
        if [ -z "$newest" ] || [ "$snap" -nt "$newest" ]; then
            newest="$snap"
        fi
    done
    [ -n "$newest" ] && printf '%s\n' "${newest%/}"
}

if [ -n "${REPO:-}" ] && [ -z "$SRC" ]; then
    CAND="$HUB/models--${REPO//\//--}"
    [ -d "$CAND" ] || {
        echo "not in cache: $REPO (looked for $CAND)" >&2
        echo "download the original checkpoint first, or check the exact org/model spelling" >&2
        exit 2
    }
    SRC="$(newest_original_snapshot "$CAND")"
    [ -n "$SRC" ] || {
        echo "no original DeepSeek V4.1 checkpoint under $CAND" >&2
        echo "newest snapshot: $(newest_snapshot "$CAND")" >&2
        echo "oQ needs config.json model_type=deepseek_v41, no omlx_deepseek_v41, and model.safetensors.index.json" >&2
        exit 2
    }
fi

if [ -z "$SRC" ]; then
    # Auto-discover: newest original deepseek_v41 snapshot in the HF cache.
    # Converted/quantized outputs are deliberately excluded.
    MATCHES=""
    for model_dir in "$HUB"/models--*; do
        [ -d "$model_dir/snapshots" ] || continue
        newest="$(newest_original_snapshot "$model_dir")"
        [ -n "$newest" ] || continue
        MATCHES="$MATCHES${MATCHES:+$'\n'}$newest"
    done
    NMATCHES=0
    [ -n "$MATCHES" ] && NMATCHES=$(printf '%s\n' "$MATCHES" | wc -l | tr -d ' ')
    if [ "$NMATCHES" -eq 1 ]; then
        SRC="$MATCHES"
    else
        echo "cannot infer original DeepSeek V4.1 source ($NMATCHES matches):" >&2
        printf '%s\n' "$MATCHES" >&2
        echo "pass --src <snapshot-dir> or <org/model>" >&2
        exit 2
    fi
fi

SRC="$(cd "$SRC" && pwd)"
is_original_source "$SRC" || {
    echo "missing or converted source: $SRC" >&2
    echo "expected an original checkpoint (model_type=deepseek_v41, no omlx_deepseek_v41)" >&2
    exit 2
}

if [ -n "${REPO:-}" ]; then
    MODEL_TAG="${REPO##*/}"
else
    case "$SRC" in
        *models--*)
            _tag="${SRC%%/snapshots/*}"
            _tag="${_tag##*models--}"
            MODEL_TAG="${_tag#*--}"
            ;;
        *) MODEL_TAG="$(basename "$SRC")" ;;
    esac
fi

TAG="$MODEL_TAG-oQ${OQ_LEVEL}e"
BUNDLE="/tmp/calibration-se-$TAG.txt"
OUT="$MODELS_OUT/$TAG-$VERSION"
NPZ="$OQUP/imatrix-$TAG-$VERSION.npz"
LOG="$OQUP/oq${OQ_LEVEL}e-$VERSION.log"
RUNNER="$OQUP/run_oq${OQ_LEVEL}e_$VERSION.py"
VERIFY_PY="$OQUP/verify_deepseek_v41_oq.py"

STOCK_OUT="$MODELS_OUT/$TAG-stock"
STOCK_NPZ="$OQUP/imatrix-stock-$TAG.npz"
STOCK_LOG="$OQUP/oq${OQ_LEVEL}e-$MODEL_TAG-stock.log"
STOCK_RUNNER="$OQUP/run_oq${OQ_LEVEL}e_${MODEL_TAG}_stock.py"
STOCK_PIDFILE="$OQUP/oq${OQ_LEVEL}e-$MODEL_TAG-stock.pid"
PIDFILE="$OQUP/oq${OQ_LEVEL}e-$VERSION.pid"
trap 'rm -f "$PIDFILE" "$STOCK_PIDFILE"' EXIT

write_build_json() { # <out> <intent> <ngram-label> <bundle> <samples> <seqlen> <stream-label>
    local out="$1" intent="$2" nlabel="$3" bundle="${4:-}" samples="$5" seqlen="$6" stream_label="$7"
    local csha="" crepo ocommit obranch now
    if [ -n "$bundle" ] && [ -f "$bundle" ]; then
        csha="$(shasum -a 256 "$bundle" 2>/dev/null | awk '{print $1}')"
    fi
    crepo="$(git -C "$CORPUS_REPO" rev-parse HEAD 2>/dev/null || true)"
    ocommit="$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || true)"
    obranch="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    now="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    cat > "$out/build.json" <<EOF
{
  "family": "deepseek_v41",
  "src": "$SRC",
  "oq_level": $OQ_LEVEL,
  "enhanced": true,
  "ngram_bits": "$nlabel",
  "preserve_mtp": $PRESERVE_MTP,
  "stream_calibration": "$stream_label",
  "imatrix_samples": $samples,
  "imatrix_seq_length": $seqlen,
  "calib_dataset_intent": "$intent",
  "corpus_bundle": "$bundle",
  "corpus_bundle_sha256": "$csha",
  "corpus_repo_commit": "$crepo",
  "omlx_repo": "$OMLX_REPO",
  "omlx_branch": "$obranch",
  "omlx_commit": "$ocommit",
  "created": "$now"
}
EOF
}

run_heldout_ppl() { # <quant-dir> <ppl-log-path>
    if [ "${OQ_SKIP_PPL:-0}" = "1" ]; then
        echo "== heldout PPL skipped (OQ_SKIP_PPL=1) =="
        return 0
    fi
    local ppl_script="$CORPUS_REPO/scripts/ppl_heldout.py"
    if [ ! -f "$ppl_script" ]; then
        echo "WARNING: heldout scorer missing, skipping: $ppl_script" >&2
        return 0
    fi
    local args=() p
    for p in ${PPL_FILES:-heldout-se2.txt heldout-se.txt heldout-general.txt}; do
        [[ "$p" == /* ]] || p="$CORPUS_REPO/eval/$p"
        args+=("$p")
    done
    PPL_CHUNK="${PPL_CHUNK:-2048}"
    echo "== heldout PPL (chunk $PPL_CHUNK; keep the oMLX server stopped) =="
    echo "   files: ${args[*]}"
    if "$VENV_PY" "$ppl_script" --model "$1" --files "${args[@]}" --chunk "$PPL_CHUNK" > "$2" 2>&1; then
        cat "$2"
        echo "== heldout PPL recorded: $2 =="
    else
        echo "WARNING: heldout scoring failed — output in $2 (the quant itself is fine)" >&2
        cat "$2" 2>/dev/null || true
    fi
    return 0
}

ensure_stock() {
    if [ -f "$STOCK_OUT/build.json" ] && [ -f "$STOCK_OUT/quantization_report.json" ]; then
        if "$VENV_PY" - "$STOCK_OUT" "$SRC" "$OQ_LEVEL" "$PRESERVE_MTP" \
            "$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || true)" <<'PY'
import json, sys

out, src, level, mtp, omlx = sys.argv[1:6]
b = json.load(open(f"{out}/build.json"))
ok = (
    b.get("family") == "deepseek_v41"
    and b.get("src") == src
    and float(b.get("oq_level")) == float(level)
    and b.get("preserve_mtp") == int(mtp)
    and b.get("omlx_commit") == omlx
    and b.get("calib_dataset_intent") == "stock-default"
)
print("stock reuse check:", "OK" if ok else "STALE")
sys.exit(0 if ok else 1)
PY
        then
            echo "== stock baseline exists (reusing): $STOCK_OUT =="
            return 0
        fi
        echo "== stock baseline is stale (source, params or oMLX commit changed) — rebuilding =="
    elif [ -e "$STOCK_OUT" ]; then
        echo "== stock dir exists without build metadata — rebuilding =="
    fi
    if [ -e "$STOCK_OUT" ]; then
        rm -rf "$STOCK_OUT"
    fi
    echo "== ensuring stock baseline (V4.1 output may be hundreds of GB) =="
    cat > "$STOCK_RUNNER" <<EOF
from omlx.oq import quantize_oq_streaming
quantize_oq_streaming(
    model_path="$SRC",
    output_path="$STOCK_OUT",
    oq_level=$OQ_LEVEL, enhanced=True,
    preserve_mtp=$MTP_PY,
    imatrix_cache_path="$STOCK_NPZ",
    imatrix_reuse_cache=False,
)
EOF
    echo "$$" > "$STOCK_PIDFILE"
    if [ -f "$STOCK_LOG" ]; then mv "$STOCK_LOG" "$STOCK_LOG.prev"; fi
    echo "== launching stock build (log: $STOCK_LOG) =="
    if ! "$VENV_PY" "$STOCK_RUNNER" > "$STOCK_LOG" 2>&1; then
        echo "WARNING: stock baseline build failed (see $STOCK_LOG)." >&2
        echo "         Continuing without it; suppress retries with OQ_SKIP_STOCK=1." >&2
        rm -f "$STOCK_PIDFILE"
        return 1
    fi
    rm -f "$STOCK_PIDFILE"
    echo "== stock built, verifying =="
    "$VENV_PY" "$VERIFY_PY" "$STOCK_OUT" "$BUNDLE" "$OQ_LEVEL" "default" "stock" \
        "$PRESERVE_MTP" "auto"
    write_build_json "$STOCK_OUT" "stock-default" "default" "" 128 512 "auto"
    run_heldout_ppl "$STOCK_OUT" "$OQUP/ppl-stock-$TAG.log"
    echo "== stock baseline ready: $STOCK_OUT =="
}

echo "== omlx_deepseek_v41_oq${OQ_LEVEL}e $VERSION =="
echo "corpus repo : $CORPUS_REPO"
echo "omlx repo   : $OMLX_REPO ($(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'NOT A GIT CHECKOUT'))"
echo "source      : $SRC"
echo "output      : $OUT"
echo "imatrix     : $NPZ"
if [ "$PRESERVE_NGRAM" = "1" ]; then
    echo "engram      : source FP8 (preserved)"
else
    echo "engram      : ${NGRAM_BITS}-bit (group 32)"
fi
echo "stream      : $STREAM_LABEL"
echo "stock       : $STOCK_OUT (OQ_SKIP_STOCK default 1)"

[ -f "$VENV_PY" ] || { echo "missing venv python: $VENV_PY" >&2; exit 1; }
BRANCH="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$BRANCH" != "feat/custom-corpus-ngram-q8" ]; then
    echo "WARNING: omlx repo is on '$BRANCH', expected feat/custom-corpus-ngram-q8" >&2
fi

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "refusing: '$VERSION' appears to be already running (pid $(cat "$PIDFILE"))" >&2
    echo "pidfile: $PIDFILE — if no such build is running, remove it and retry" >&2
    exit 1
fi

case "$VERSION" in
    arm-*)
        if [ -e "$OUT" ]; then
            echo "refusing to overwrite protected arm version: $OUT" >&2
            echo "delete it manually (rm -rf) if you really want to rebuild it" >&2
            exit 1
        fi
        ;;
    *)
        if [ -e "$OUT" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "dry run: would overwrite existing output: $OUT"
            else
                echo "== overwriting existing output: $OUT =="
                rm -rf "$OUT"
            fi
        fi
        ;;
esac

echo "== writing verify helper $VERIFY_PY =="
mkdir -p "$OQUP" "$MODELS_OUT"
cat > "$VERIFY_PY" <<'PY'
import json
import sys

out, bundle, level, ngram_spec, mode, mtp_spec, stream_spec = sys.argv[1:8]
level = float(level)
mtp = int(mtp_spec)
config = json.load(open(f"{out}/config.json"))
report = json.load(open(f"{out}/quantization_report.json"))
spec = config.get("omlx_deepseek_v41") or {}
tables = spec.get("engram_tables") or {}
quantized = spec.get("quantized_modules") or {}
engram = report.get("engram") or {}
allocation = report.get("allocation")
applied = report.get("imatrix_applied_modules") or []
failures = []

def check(name, ok, detail=""):
    print(f"{name:22s}: {'OK' if ok else 'FAILED'}{(' — ' + detail) if detail else ''}")
    if not ok:
        failures.append(name)

print(f"engram tables        : {len(tables)}")
print(f"quantized modules    : {len(quantized)}")
print(f"allocation           : {allocation}")
print(f"imatrix entries      : {len(applied)}")
print(f"engram storage       : {engram.get('precision') or engram.get('bits')} "
      f"(override {report.get('engram_bits_override')})")
print(f"calibration          : {report.get('calibration')}")

if ngram_spec == "preserved":
    expected_bits = None
elif ngram_spec == "default":
    expected_bits = max(int(level), 4)
else:
    expected_bits = int(ngram_spec.split(":")[1])

if ngram_spec == "preserved":
    # The FP8 passthrough leaves no per-tensor quantization entry; verify the
    # budget report says source precision and every table has no affine bits.
    ngram_ok = (
        bool(tables)
        and engram.get("precision") == "source"
        and all(t.get("bits") is None for t in tables.values())
    )
    ngram_detail = "source FP8"
else:
    ngram_ok = (
        bool(tables)
        and engram.get("bits") == expected_bits
        and all(
            t.get("bits") == expected_bits and t.get("group_size") == 32
            for t in tables.values()
        )
    )
    ngram_detail = f"expected {expected_bits}"
check("engram width", ngram_ok, ngram_detail)

override_ok = (
    report.get("engram_bits_override") is None
    if ngram_spec in ("default", "preserved")
    else report.get("engram_bits_override") == expected_bits
)
check("engram override", override_ok)
check("oq level", float(report.get("oq_level", -1)) == level)
check("preserve mtp", spec.get("preserve_mtp") == bool(mtp))
draft = int(report.get("preserved_source_draft_tensors", -1))
check("draft tensors", draft > 0 if mtp else draft == 0, f"count {draft}")

if level < 4:
    cal = report.get("calibration")
    if not isinstance(cal, dict):
        check("calibration block", False, repr(cal))
        cal = {}
    check("allocation", allocation == "measured_layer_sensitivity_affine")
    calib_used = cal.get("calib_dataset")
    sens_used = cal.get("sensitivity_calib_dataset")
    if mode == "stock":
        check("custom corpus excluded", calib_used != bundle, str(calib_used))
        check("sensitivity excluded", sens_used != bundle, str(sens_used))
    else:
        check("custom corpus used", calib_used == bundle, str(calib_used))
        check("sensitivity used", sens_used == bundle, str(sens_used))
    check("fresh imatrix", cal.get("imatrix_cache_reused") == False)
    check("imatrix applied", bool(applied))
    expected_stream = None if stream_spec == "auto" else stream_spec == "true"
    if expected_stream is None:
        check("streamed calibration", cal.get("calibration_streaming") == True)
    else:
        check(
            "streamed calibration",
            cal.get("calibration_streaming") == expected_stream,
            f"expected {expected_stream}",
        )
else:
    check("calibration", report.get("calibration") == "not_needed_no_linear_requantization")
    check("source precision", allocation == "original_precision_fits_independent_remaining_budget")
    check("no imatrix", applied == [])

print("VERIFY:", "OK" if not failures else "FAILED")
if failures:
    print("failed checks:", ", ".join(failures))
sys.exit(0 if not failures else 1)
PY

if [ "$DRY_RUN" -eq 1 ]; then
    if [ -f "$STOCK_OUT/build.json" ] && [ -f "$STOCK_OUT/quantization_report.json" ]; then
        echo "dry run: stock baseline exists (would reuse): $STOCK_OUT"
    elif [ "${OQ_SKIP_STOCK:-1}" = "1" ]; then
        echo "dry run: stock baseline skipped by default (OQ_SKIP_STOCK=1)"
    else
        echo "dry run: stock baseline missing — the next real run builds it first: $STOCK_OUT"
    fi
elif [ "${OQ_SKIP_STOCK:-1}" = "1" ]; then
    echo "OQ_SKIP_STOCK=1 (DeepSeek default): not ensuring the stock baseline"
else
    ensure_stock || true
fi

echo "== building bundle =="
if [ -n "$CORPUS_FILE" ]; then
    BUNDLE="$CORPUS_FILE"
    if [ ! -s "$BUNDLE" ]; then
        echo "CORPUS_FILE bundle missing or empty: $BUNDLE" >&2
        exit 1
    fi
    echo "  using CORPUS_FILE override: $BUNDLE (vendor append skipped)"
else
    cat "$CORPUS_REPO"/calibration/*.txt > "$BUNDLE"
    for vslice in "$CORPUS_REPO"/vendor/jundot-oqe/*.txt; do
        [ -f "$vslice" ] || continue
        _slicename="$(basename "$vslice" .txt)"
        case ",$VENDOR_SLICES," in
            *",$_slicename,"*) ;;
            *) echo "  - vendor $_slicename (skipped by VENDOR_SLICES)"; continue ;;
        esac
        printf '\n---\n\n' >> "$BUNDLE"
        cat "$vslice" >> "$BUNDLE"
        echo "  + vendor $(basename "$vslice")"
    done
fi
wc -c "$BUNDLE"

echo "== writing runner $RUNNER =="
cat > "$RUNNER" <<EOF
from omlx.oq import quantize_oq_streaming
quantize_oq_streaming(
    model_path="$SRC",
    output_path="$OUT",
    oq_level=$OQ_LEVEL, enhanced=True,
    preserve_mtp=$MTP_PY,
    calib_dataset="$BUNDLE",
    sensitivity_calib_dataset="$BUNDLE",
$NGRAM_LINE
$STREAM_LINE
    imatrix_cache_path="$NPZ",
    imatrix_reuse_cache=False,
    imatrix_num_samples=$OQ_SAMPLES, imatrix_seq_length=$OQ_SEQLEN,
)
EOF

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: runner written, not launched"
    exit 0
fi

echo "$$" > "$PIDFILE"
if [ -f "$LOG" ]; then mv "$LOG" "$LOG.prev"; fi
echo "== launching (log: $LOG) =="
"$VENV_PY" "$RUNNER" > "$LOG" 2>&1
rm -f "$PIDFILE"
echo "== quantize returned, verifying =="
"$VENV_PY" "$VERIFY_PY" "$OUT" "$BUNDLE" "$OQ_LEVEL" "$NGRAM_VERIFY" "custom" \
    "$PRESERVE_MTP" "$STREAM_LABEL"
write_build_json "$OUT" "custom-bundle" "$NGRAM_LABEL" "$BUNDLE" "$OQ_SAMPLES" "$OQ_SEQLEN" "$STREAM_LABEL"
run_heldout_ppl "$OUT" "$OQUP/ppl-$TAG-$VERSION.log"
echo "== done: $OUT =="
