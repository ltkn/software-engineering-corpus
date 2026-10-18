#!/usr/bin/env bash
# omlx_oq4e.sh — redo an oQ4e quant of Qwen3.8-Flash-Next on the oMLX branch.
#
# Runs on the quant machine (M3 Max). Builds the calibration bundle from
# this repo's calibration/*.txt, launches quantize_oq_streaming with the
# custom corpus + Q8 N-gram table, then verifies the report and config.
#
# Control arms (README "Building oQ quants"):
#   Arm A — stock baseline, ensured automatically before the requested
#           build: <model>-oQ<level>e-stock, oMLX's own default calibration
#           (the built-in oqe_code_multilingual corpus, default N-gram table
#           width) with no custom corpus and no vendor slices. Built once
#           per (source model, level, MTP setting), then reused.
#   Arm B — generic text through the same pipeline:
#           CORPUS_FILE=bundles/generic.txt ... arm-b-generic
#           (bundle built once by scripts/make_bundles.py). C-vs-B isolates
#           the corpus text; C-vs-stock is the headline comparison.
#
# Output policy: rerunning the same <version> overwrites that quant in place
# (previous log moves to *.log.prev; <out>/build.json records what went in —
# source snapshot, bundle sha256, corpus + oMLX commits, and the imatrix
# sampling config — samples × seq length). 'stock' is a
# reserved version name and arm-* versions refuse overwrite. A pidfile in
# $OQUP refuses concurrent runs of the same version.
#
# After a completed build the heldout PPL runs automatically via
# scripts/ppl_heldout.py — eval/heldout-se2.txt + heldout-se.txt +
# heldout-general.txt at chunk 2048 (the stock baseline too, but only when
# it actually rebuilds). Keep the oMLX server stopped while the script
# runs; scoring shares the host with serving. Numbers also persist under
# $OQUP/ppl-*.log.
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
#   <version>   experiment suffix, e.g. coder-8bit-ngram-mtp. Same-name
#               reruns overwrite in place (see output policy); 'stock' is
#               reserved and 'arm-*' names are protected. Without <org/model>,
#               the source is auto-discovered (exactly one qwen4_exp match
#               required).
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
#   OQ_SAMPLES  imatrix samples, default 99999 — every calibration window is
#               read (the subsample was what cost the first q8 build ~1%
#               NLL/token vs stock on the 23k-token heldout). "All" scales to
#               any sane bundle size; pass e.g. 128 to reproduce the old POC
#               builds bit-for-bit.
#   OQ_SEQLEN   imatrix sequence length, default 512
#   PRESERVE_MTP  keep the native MTP draft head (Lightning MTP), default 1.
#               Set to 0 for MTP-free outputs (reproduces pre-MTP runs).
#   PRESERVE_NGRAM_TABLE  keep the PLE N-gram table unquantized (BF16
#               passthrough) instead of quantizing it, default 0. Set to 1
#               for the unquantized-table baseline to bench quantized-table
#               variants against. Conflicts with the ngram_bits positional.
#   HF_HUB_CACHE  huggingface hub cache for source auto-discovery
#               (default: ~/.cache/huggingface/hub)
#   VENDOR_SLICES comma-separated upstream slices to append
#               (default: code,tool_calling,chat,reasoning). Empty string
#               skips the append entirely — the authored-only arm.
#   CORPUS_FILE path to a prebuilt calibration bundle (absolute, or relative
#               to this repo); replaces the assembled bundle entirely, so
#               VENDOR_SLICES is ignored. Control arms use bundles/generic.txt.
#   OQ_SKIP_STOCK set to 1 to skip ensuring the stock baseline this run.
#   OQ_SKIP_PPL   set to 1 to skip the post-build heldout PPL scoring.
#   PPL_FILES     heldout files to score, relative to eval/ (default:
#                 heldout-se2.txt heldout-se.txt heldout-general.txt).
#   PPL_CHUNK     PPL scoring window, default 2048.
#
# Examples:
#   scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-8bit-ngram-mtp 8
#   scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-4bit-ngram 4
#   PRESERVE_NGRAM_TABLE=1 scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-ngram-fp
#   CORPUS_FILE=bundles/generic.txt scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next arm-b-generic 8
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

case "$VERSION" in
    stock)
        echo "'stock' is reserved: every run ensures the stock baseline automatically" >&2
        echo "(<model>-oQ<level>e-stock). Run your own <version> name as usual." >&2
        exit 2
        ;;
esac
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
# 99999 is "read every calibration window": the seeded sampler only subsamples
# when the pool is larger than num_samples, and no realistic bundle reaches 50M
# tokens. The old 128 default is what the first q8 build used; its ~1% deficit
# vs stock on heldout-se2 shrank to a tie once the whole corpus was read.
OQ_SAMPLES="${OQ_SAMPLES:-99999}"
OQ_SEQLEN="${OQ_SEQLEN:-512}"
PRESERVE_MTP="${PRESERVE_MTP:-1}"
if [ "$PRESERVE_MTP" = "1" ]; then MTP_PY=True; else MTP_PY=False; fi
PRESERVE_NGRAM="${PRESERVE_NGRAM_TABLE:-0}"
VENDOR_SLICES_EXPLICIT=0
if [ -n "${VENDOR_SLICES+x}" ]; then VENDOR_SLICES_EXPLICIT=1; fi
# No colon in the default: an explicitly EMPTY VENDOR_SLICES must stay
# empty (the authored-only arm); only an UNSET one gets the full mix.
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
VERIFY_PY="$OQUP/verify_oq.py"

# Stock baseline paths (arm A) — keyed by source model + level so different
# models or levels never share stock artifacts.
STOCK_OUT="$MODELS_OUT/$MODEL_TAG-oQ${OQ_LEVEL}e-stock"
STOCK_NPZ="$OQUP/imatrix-stock-$MODEL_TAG-oQ${OQ_LEVEL}e.npz"
STOCK_LOG="$OQUP/oq${OQ_LEVEL}e-$MODEL_TAG-stock.log"
STOCK_RUNNER="$OQUP/run_oq${OQ_LEVEL}e_${MODEL_TAG}_stock.py"
STOCK_PIDFILE="$OQUP/oq${OQ_LEVEL}e-$MODEL_TAG-stock.pid"
PIDFILE="$OQUP/oq${OQ_LEVEL}e-$VERSION.pid"
trap 'rm -f "$PIDFILE" "$STOCK_PIDFILE"' EXIT

write_build_json() { # <out-dir> <calib-intent> <ngram-label> <bundle-or-""> [samples] [seqlen]
    local out="$1" intent="$2" nlabel="$3" bundle="${4:-}" csha=""
    # Stock never passes imatrix overrides, so its sampling is the library
    # default (128 x 512) even when OQ_SAMPLES/OQ_SEQLEN are overridden for a
    # custom arm in the same run; record what each arm actually used.
    local samples="${5:-128}" seqlen="${6:-512}"
    if [ -n "$bundle" ] && [ -f "$bundle" ]; then
        csha="$(shasum -a 256 "$bundle" 2>/dev/null | awk '{print $1}')"
    fi
    local crepo ocommit obranch now
    crepo="$(git -C "$CORPUS_REPO" rev-parse HEAD 2>/dev/null || true)"
    ocommit="$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || true)"
    obranch="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    now="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    cat > "$out/build.json" <<EOF
{
  "src": "$SRC",
  "oq_level": $OQ_LEVEL,
  "ngram_bits": "$nlabel",
  "preserve_mtp": $PRESERVE_MTP,
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
    # Arm A — the stock oMLX baseline: the tool's own default calibration
    # (oqe_code_multilingual built-in corpus; code_multilingual sensitivity
    # set; default N-gram table width), no custom corpus, no vendor slices.
    # Built once per (source model, level, MTP setting), then reused; the
    # reuse check reads <out>/build.json. Only preserve_mtp deviates from a
    # truly-default run, matched so serving comparisons stay apples-to-apples.
    if [ -f "$STOCK_OUT/build.json" ] && [ -f "$STOCK_OUT/oq_imatrix_report.json" ]; then
        if "$VENV_PY" - "$STOCK_OUT" "$SRC" "$OQ_LEVEL" "$PRESERVE_MTP" <<'PY'
import json, sys

out, src, level, mtp = sys.argv[1:5]
b = json.load(open(f"{out}/build.json"))
ok = (
    b.get("src") == src
    and b.get("oq_level") == int(level)
    and b.get("preserve_mtp") == int(mtp)
    and b.get("calib_dataset_intent") == "stock-default"
)
print("stock reuse check:", "OK" if ok else "STALE")
sys.exit(0 if ok else 1)
PY
        then
            echo "== stock baseline exists (reusing): $STOCK_OUT =="
            return 0
        fi
        echo "== stock baseline is stale (source or params changed) — rebuilding =="
    elif [ -e "$STOCK_OUT" ]; then
        echo "== stock dir exists without build metadata — rebuilding =="
    fi
    if [ -e "$STOCK_OUT" ]; then
        rm -rf "$STOCK_OUT"
    fi
    echo "== ensuring stock baseline (built once per source model + level) =="
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
        echo "         Continuing without it; rerun any time for the baseline," >&2
        echo "         or suppress retries with OQ_SKIP_STOCK=1." >&2
        rm -f "$STOCK_PIDFILE"
        return 1
    fi
    rm -f "$STOCK_PIDFILE"
    echo "== stock built, verifying =="
    "$VENV_PY" "$VERIFY_PY" "$STOCK_OUT" "$BUNDLE" "$OQ_LEVEL" "default" "stock"
    write_build_json "$STOCK_OUT" stock-default "default" "" 128 512
    run_heldout_ppl "$STOCK_OUT" "$OQUP/ppl-stock-$MODEL_TAG-oQ${OQ_LEVEL}e.log"
    echo "== stock baseline ready: $STOCK_OUT =="
}

echo "== omlx_oq${OQ_LEVEL}e $VERSION =="
echo "corpus repo : $CORPUS_REPO"
echo "omlx repo   : $OMLX_REPO ($(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'NOT A GIT CHECKOUT'))"
echo "source      : $SRC"
echo "output      : $OUT"
echo "imatrix     : $NPZ"
echo "stock       : $STOCK_OUT (arm A, ensured once, reused after)"

[ -f "$SRC/config.json" ] || { echo "missing $SRC/config.json" >&2; exit 1; }
[ -f "$VENV_PY" ] || { echo "missing venv python: $VENV_PY" >&2; exit 1; }
BRANCH="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$BRANCH" != "feat/custom-corpus-ngram-q8" ]; then
    echo "WARNING: omlx repo is on '$BRANCH', expected feat/custom-corpus-ngram-q8" >&2
fi

# One build per version at a time. A stale pidfile (run killed -9) is
# removed by hand; after a normal exit the file is gone, so kill -0 on a
# dead pid self-heals.
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "refusing: '$VERSION' appears to be already running (pid $(cat "$PIDFILE"))" >&2
    echo "pidfile: $PIDFILE — if no such build is running, remove it and retry" >&2
    exit 1
fi

# Overwrite policy: ordinary <version> names are replaced in place — that is
# how corpus iterations rerun. arm-* comparators are protected so a rerun
# cannot destroy the baseline being compared against.
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

out, bundle, level, ngram_spec, mode = sys.argv[1:6]
level = int(level)
report = json.load(open(f"{out}/oq_imatrix_report.json"))
q = json.load(open(f"{out}/config.json"))["quantization"]
ngram = {k: v for k, v in q.items() if "ngram" in k}

print(f"calib_dataset : {report['calib_dataset']}")
print(f"cache_reused  : {report['cache_reused']}")
print(f"imatrix entries: {report['entry_count']}, missing: {len(report['missing'])}, mismatched: {len(report['mismatched'])}")
print(f"global        : bits={q.get('bits')} group_size={q.get('group_size')}")
print(f"ngram shards  : {len(ngram)}, e.g. {next(iter(ngram.values())) if ngram else None}")

if ngram_spec == "preserved":
    # Passthrough leaves no per-layer quantization entry: the shards
    # must be absent from the quantization dict, not merely high-bit.
    ngram_ok = len(ngram) == 0
elif ngram_spec == "default":
    # Stock baseline: the tool's own table width stands; report it, don't
    # gate on it.
    ngram_ok = True
else:
    _, bits = ngram_spec.split(":")
    ngram_ok = bool(ngram) and all(
        v.get("bits") == int(bits) and v.get("group_size") == 32
        for v in ngram.values()
    )

if mode == "stock":
    calib_ok = report["calib_dataset"] != bundle  # never the custom bundle
else:
    calib_ok = report["calib_dataset"] == bundle

ok = (
    calib_ok
    and report["cache_reused"] is False
    and report["entry_count"] > 0
    and q.get("bits") == level
    and ngram_ok
)
print("VERIFY:", "OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
PY

if [ "$DRY_RUN" -eq 1 ]; then
    if [ -f "$STOCK_OUT/build.json" ] && [ -f "$STOCK_OUT/oq_imatrix_report.json" ]; then
        echo "dry run: stock baseline exists (would reuse): $STOCK_OUT"
    else
        echo "dry run: stock baseline missing — the first real run builds it before the quant: $STOCK_OUT"
    fi
elif [ "${OQ_SKIP_STOCK:-0}" = "1" ]; then
    echo "OQ_SKIP_STOCK=1: not ensuring the stock baseline this run"
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
    # Vendored upstream slices (Apache-2.0, see vendor/jundot-oqe/ATTRIBUTION.md)
    # append after authored files; token-stream calibration concatenates anyway.
    # VENDOR_SLICES selects the mix (default: all four). Drop 'code' to test
    # whether trivial code pairs contribute anything beyond benchmark shape:
    #   VENDOR_SLICES=chat,tool_calling,reasoning scripts/omlx_oq4e.sh ...
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
"$VENV_PY" "$VERIFY_PY" "$OUT" "$BUNDLE" "$OQ_LEVEL" "$NGRAM_VERIFY" "custom"
write_build_json "$OUT" custom-bundle "$NGRAM_LABEL" "$BUNDLE" "$OQ_SAMPLES" "$OQ_SEQLEN"
run_heldout_ppl "$OUT" "$OQUP/ppl-$MODEL_TAG-oQ${OQ_LEVEL}e-$VERSION.log"
echo "== done: $OUT =="
