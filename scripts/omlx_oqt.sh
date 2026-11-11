#!/usr/bin/env bash
# omlx_oqt.sh — build an oQ-T ("teacher-matched") quant in one command.
#
#   scripts/omlx_oqt.sh <level> <version>
#
#   scripts/omlx_oqt.sh 4 v1        # oQ4t, output ~/models-out/<Model>-oQ4t-v1
#   scripts/omlx_oqt.sh 3 v1        # oQ3t
#
# What it does, in order:
#   1. finds the source model (newest Qwen3.8-Flash-Next snapshot in the
#      Hugging Face cache, or SRC=<dir>)
#   2. builds the calibration bundle from this repo's calibration/*.txt
#      (or CORPUS_FILE=<file>)
#   3. runs oMLX quantize_oq_streaming with streaming + oQ-T on:
#        imatrix + sensitivity pass  -> quant plan  -> oQ-T sweep (GPTQ per
#        block, quantized outputs fed forward)  -> writer
#      Everything streams one decoder block at a time, so it fits in 128 GB.
#   4. checks the output and prints the oQ-T report (oQ-T vs oQe error)
#   5. writes build.json and scores the heldouts
#
# A crash or Ctrl-C is safe: rerun the same command with OQT_OVERWRITE=1 and
# the sweep resumes from its per-layer cache.
#
# Options (environment variables):
#   SRC=<dir>          source checkpoint (BF16 safetensors dir) instead of auto-discovery
#   CORPUS_FILE=<file> calibration text instead of calibration/*.txt
#   OQT_OVERWRITE=1    replace an existing output with the same name
#   OQT_COMPARE=1      also build plain oQe from the same bundle, and score both
#   OQ_SAMPLES=256     calibration windows (x OQ_SEQLEN tokens)
#   OQ_SEQLEN=2048     window length
#   NGRAM_BITS=8       n-gram table bits (2 3 4 5 6 8)
#   PRESERVE_MTP=1     keep the MTP draft head
#   OQ_SKIP_PPL=1      skip heldout scoring
#   OMLX_REPO, VENV_PY, OQUP, MODELS_OUT   paths (defaults below)
#   --dry-run          (last argument) print the plan and write the runner only
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
LEVEL="${1:-}"; VERSION="${2:-}"
[ -n "$LEVEL" ] && [ -n "$VERSION" ] || usage
case "$LEVEL" in 2|3|4|5|6|8) ;; *) echo "level must be one of 2 3 4 5 6 8 (got '$LEVEL')" >&2; exit 2 ;; esac
case "$VERSION" in */*|.*|"") echo "version must be a plain name like v1" >&2; exit 2 ;; esac
DRY_RUN=0; [ "${3:-}" = "--dry-run" ] && DRY_RUN=1

CORPUS_REPO="$(cd "$(dirname "$0")/.." && pwd)"
OMLX_REPO="${OMLX_REPO:-$HOME/dev/omlx}"
VENV_PY="${VENV_PY:-$OMLX_REPO/.venv-3.12/bin/python}"
OQUP="${OQUP:-$HOME/oqup}"
MODELS_OUT="${MODELS_OUT:-$HOME/models-out}"
OQ_SAMPLES="${OQ_SAMPLES:-256}"
OQ_SEQLEN="${OQ_SEQLEN:-2048}"
NGRAM_BITS="${NGRAM_BITS:-8}"
PRESERVE_MTP="${PRESERVE_MTP:-1}"
HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"
mkdir -p "$OQUP" "$MODELS_OUT"

say() { printf '\n== %s ==\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
say "preflight"
[ -x "$VENV_PY" ] || die "oMLX venv python not found: $VENV_PY (set OMLX_REPO or VENV_PY)"
"$VENV_PY" -c "import omlx.oqt" 2>/dev/null \
    || die "this oMLX checkout has no oQ-T. In $OMLX_REPO run: git fetch && git checkout feat/oqt"
case " 2 3 4 5 6 8 " in *" $NGRAM_BITS "*) ;; *) die "NGRAM_BITS must be one of 2 3 4 5 6 8" ;; esac

if [ -z "${SRC:-}" ]; then
    MATCHES=""
    for model_dir in "$HUB"/models--*; do
        [ -d "$model_dir/snapshots" ] || continue
        newest=""
        for snap in "$model_dir"/snapshots/*/; do
            [ -f "$snap/config.json" ] && grep -q 'qwen4_exp' "$snap/config.json" || continue
            if [ -z "$newest" ] || [ "$snap" -nt "$newest" ]; then newest="$snap"; fi
        done
        [ -n "$newest" ] && MATCHES="$MATCHES${MATCHES:+$'\n'}${newest%/}"
    done
    n=0; [ -n "$MATCHES" ] && n=$(printf '%s\n' "$MATCHES" | wc -l | tr -d ' ')
    [ "$n" = "1" ] || { printf '%s\n' "$MATCHES" >&2; die "found $n Qwen3.8-Flash-Next snapshots; pass SRC=<dir>"; }
    SRC="$MATCHES"
fi
[ -f "$SRC/config.json" ] || die "no config.json in SRC=$SRC"
if grep -q 'deepseek_v41' "$SRC/config.json"; then
    die "oQ-T does not support DeepSeek V4.1 yet; use scripts/omlx_deepseek_v41_oq3e.sh"
fi
grep -q 'qwen4_exp' "$SRC/config.json" \
    || echo "WARNING: source is not qwen4_exp; oQ-T streams only oMLX's streamable layouts" >&2

case "$SRC" in
    *models--*) _t="${SRC%%/snapshots/*}"; _t="${_t##*models--}"; MODEL_TAG="${_t#*--}" ;;
    *) MODEL_TAG="$(basename "$SRC")" ;;
esac

OUT="$MODELS_OUT/$MODEL_TAG-oQ${LEVEL}t-$VERSION"
CMP_OUT="$MODELS_OUT/$MODEL_TAG-oQ${LEVEL}e-$VERSION-cmp"
CACHE="$OQUP/oqt-cache-$MODEL_TAG-oQ${LEVEL}-$VERSION"
NPZ="$OQUP/imatrix-oqt-$MODEL_TAG-oQ${LEVEL}-$VERSION.npz"
LOG="$OQUP/oqt-$MODEL_TAG-oQ${LEVEL}-$VERSION.log"
RUNNER="$OQUP/run_oqt_$MODEL_TAG-oQ${LEVEL}-$VERSION.py"
BUNDLE="$OQUP/calibration-oqt-$VERSION.txt"
if [ "$PRESERVE_MTP" = "1" ]; then MTP_PY=True; else MTP_PY=False; fi

for d in "$OUT" $( [ "${OQT_COMPARE:-0}" = "1" ] && echo "$CMP_OUT" ); do
    if [ -e "$d" ]; then
        [ "${OQT_OVERWRITE:-0}" = "1" ] || die "$d exists. Rerun with OQT_OVERWRITE=1 to replace it (the oQ-T cache is kept, so a rerun resumes)"
    fi
done

ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
free_gb=$(df -g "$MODELS_OUT" 2>/dev/null | awk 'NR==2 {print $4}')
src_gb=$(du -sk "$SRC/" 2>/dev/null | awk '{printf "%d", $1/1048576}')
[ "$ram_gb" -ge 96 ] || echo "WARNING: ${ram_gb} GB RAM; oQ-T is planned for the 128 GB host" >&2
[ -n "$free_gb" ] && [ "$free_gb" -lt 150 ] && echo "WARNING: only ${free_gb} GB free under $MODELS_OUT" >&2

echo "source     : $SRC (${src_gb:-?} GB)"
echo "level      : oQ${LEVEL}t   (n-gram table ${NGRAM_BITS}-bit, MTP $([ "$PRESERVE_MTP" = 1 ] && echo kept || echo stripped))"
echo "output     : $OUT"
[ "${OQT_COMPARE:-0}" = "1" ] && echo "comparison : $CMP_OUT (plain oQe, same bundle)"
echo "calibration: ${CORPUS_FILE:-$CORPUS_REPO/calibration/*.txt}  ($OQ_SAMPLES x $OQ_SEQLEN tokens)"
echo "cache      : $CACHE"
echo "log        : $LOG"
echo "machine    : ${ram_gb} GB RAM, ${free_gb:-?} GB free"

# ------------------------------------------------------------------- bundle
say "calibration bundle"
if [ -n "${CORPUS_FILE:-}" ]; then
    case "$CORPUS_FILE" in /*) ;; *) CORPUS_FILE="$CORPUS_REPO/$CORPUS_FILE" ;; esac
    [ -s "$CORPUS_FILE" ] || die "CORPUS_FILE missing or empty: $CORPUS_FILE"
    cp "$CORPUS_FILE" "$BUNDLE"
else
    cat "$CORPUS_REPO"/calibration/*.txt > "$BUNDLE"
fi
echo "$(wc -c < "$BUNDLE" | tr -d ' ') bytes -> $BUNDLE"

# ------------------------------------------------------------------- runner
write_runner() { # <runner-path> <out-dir> <teacher_matched True|False>
    cat > "$1" <<EOF
import logging, sys
logging.basicConfig(level=logging.INFO, stream=sys.stdout,
                    format="%(asctime)s %(levelname)s %(message)s")
from omlx.oq import quantize_oq_streaming
quantize_oq_streaming(
    model_path="$SRC",
    output_path="$2",
    oq_level=$LEVEL,
    enhanced=True,
    stream_calibration=True,
    teacher_matched=$3,
    oqt_cache_path="$CACHE",
    preserve_mtp=$MTP_PY,
    ngram_bits=$NGRAM_BITS,
    calib_dataset="$BUNDLE",
    sensitivity_calib_dataset="$BUNDLE",
    imatrix_cache_path="$NPZ",
    imatrix_reuse_cache=True,
    imatrix_num_samples=$OQ_SAMPLES,
    imatrix_seq_length=$OQ_SEQLEN,
)
EOF
}
write_runner "$RUNNER" "$OUT" True
echo "runner: $RUNNER"
if [ "$DRY_RUN" = "1" ]; then
    say "dry run: nothing launched"
    cat "$RUNNER"
    exit 0
fi

# -------------------------------------------------------------------- build
PIDFILE="$OQUP/oqt-$VERSION.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    die "a build named '$VERSION' is already running (pid $(cat "$PIDFILE"))"
fi
echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

[ -e "$OUT" ] && rm -rf "$OUT"
[ -f "$LOG" ] && mv "$LOG" "$LOG.prev"
say "building oQ${LEVEL}t (several hours; follow with: tail -f $LOG)"
start=$(date +%s)
if ! "$VENV_PY" "$RUNNER" > "$LOG" 2>&1; then
    tail -n 30 "$LOG" >&2
    die "build failed (full log: $LOG). Fix the cause and rerun with OQT_OVERWRITE=1 to resume"
fi
echo "built in $(( ($(date +%s) - start) / 60 )) min"

# ------------------------------------------------------------------- verify
say "checking the output"
"$VENV_PY" - "$OUT" "$LEVEL" <<'PY'
import json, sys
from pathlib import Path
out, level = Path(sys.argv[1]), int(sys.argv[2])
cfg = json.loads((out / "config.json").read_text())
q = cfg.get("quantization") or cfg.get("quantization_config") or {}
assert q.get("bits") == level, f"config quantization bits {q.get('bits')} != {level}"
assert list(out.glob("*.safetensors")), "no weight shards written"
rep = json.loads((out / "oqt_report.json").read_text())
used, s = rep["used"], rep["summary"]
assert used, "oQ-T report lists no tensors: the sweep did not reach the writer"
print(f"oQ-T tensors written : {len(used)}")
print(f"declined by writer   : {len(rep['declined_by_writer'])}")
print(f"skipped in sweep     : {len(rep['skipped_in_sweep'])} (these used plain oQe)")
if s:
    print(f"vs oQe, same bits    : median output error x{s['median_err_ratio_oqt_vs_oqe']:.2f}, "
          f"better on {s['share_tensors_improved']:.0%} of tensors")
PY

crepo="$(git -C "$CORPUS_REPO" rev-parse HEAD 2>/dev/null || true)"
ocommit="$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || true)"
obranch="$(git -C "$OMLX_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
cat > "$OUT/build.json" <<EOF
{
  "method": "oQ-T",
  "src": "$SRC",
  "oq_level": $LEVEL,
  "ngram_bits": "$NGRAM_BITS",
  "preserve_mtp": $PRESERVE_MTP,
  "imatrix_samples": $OQ_SAMPLES,
  "imatrix_seq_length": $OQ_SEQLEN,
  "corpus_bundle": "$BUNDLE",
  "corpus_bundle_sha256": "$(shasum -a 256 "$BUNDLE" | awk '{print $1}')",
  "oqt_cache": "$CACHE",
  "corpus_repo_commit": "$crepo",
  "omlx_branch": "$obranch",
  "omlx_commit": "$ocommit",
  "created": "$(date +"%Y-%m-%dT%H:%M:%S%z")"
}
EOF

# ------------------------------------------------------- optional comparison
if [ "${OQT_COMPARE:-0}" = "1" ]; then
    say "building the plain oQe comparison (same bundle, same imatrix cache)"
    CMP_RUNNER="${RUNNER%.py}_cmp.py"
    write_runner "$CMP_RUNNER" "$CMP_OUT" False
    [ -e "$CMP_OUT" ] && rm -rf "$CMP_OUT"
    "$VENV_PY" "$CMP_RUNNER" > "${LOG%.log}-cmp.log" 2>&1 \
        || die "comparison build failed (log: ${LOG%.log}-cmp.log)"
fi

# ---------------------------------------------------------------- heldouts
score() { # <quant-dir> <label>
    if [ "${OQ_SKIP_PPL:-0}" = "1" ]; then echo "heldout scoring skipped (OQ_SKIP_PPL=1)"; return 0; fi
    local files=() p
    for p in ${PPL_FILES:-heldout-se2.txt heldout-se.txt heldout-general.txt}; do
        [[ "$p" == /* ]] || p="$CORPUS_REPO/eval/$p"; files+=("$p")
    done
    local plog="$OQUP/ppl-$MODEL_TAG-oQ${LEVEL}-$VERSION-$2.log"
    local cmd=("$VENV_PY" "$CORPUS_REPO/scripts/ppl_heldout.py" --model "$1" --files "${files[@]}"
               --chunk "${PPL_CHUNK:-2048}" --json "${plog%.log}.json")
    # Reuse teacher anchors if the oQe scripts already built them for these files.
    local anchor; anchor="$(ls -t "$OQUP"/teacher-anchors-*.npz 2>/dev/null | head -1 || true)"
    [ -n "${PPL_TEACHER:-$anchor}" ] && cmd+=(--teacher "${PPL_TEACHER:-$anchor}")
    say "heldout scores: $2 (keep the oMLX server stopped)"
    if "${cmd[@]}" > "$plog" 2>&1; then cat "$plog"; else
        echo "WARNING: scoring failed, see $plog (the quant itself is fine)" >&2; fi
}
score "$OUT" oqt
[ "${OQT_COMPARE:-0}" = "1" ] && score "$CMP_OUT" oqe-cmp

say "done: $OUT"
echo "serve it: ln -s \"$OUT\" ~/.omlx/models/  (or omlx serve --model-dir $MODELS_OUT)"
