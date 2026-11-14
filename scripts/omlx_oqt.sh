#!/usr/bin/env bash
# omlx_oqt.sh — build an oQ-T ("teacher-matched") quant in one command.
#
#   scripts/omlx_oqt.sh <level> <version>
#
#   scripts/omlx_oqt.sh 4 v1        # oQ4t, output ~/models-out/<Model>-oQ4t-v1
#   scripts/omlx_oqt.sh 3 v1        # oQ3t
#
# What it does, in order:
#   1. finds the source model (newest complete BF16 snapshot of the model
#      profile's official repo in the Hugging Face cache, a variant's folder,
#      or SRC=<dir>)
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
#   OQT_MODEL=<id>     model profile, models/<id>.json (default: the only one)
#   OQT_VARIANT=<suffix>  a fine-tune named <name>-<suffix> (a folder of that name in
#                      MODELS_OUT, or an HF repo <org>/<name>-<suffix>)
#   SRC=<dir>          source checkpoint (BF16 safetensors dir) instead of auto-discovery
#   SOURCE_REPO=<org/name>  auto-discover another repo's BF16 snapshot (a fine-tune
#                      of the same architecture) instead of the official repo
#   CORPUS_FILE=<file> calibration text instead of calibration/*.txt
#   OQT_OVERWRITE=1    replace an existing output with the same name
#   OQT_COMPARE=1      also build plain oQe from the same bundle, and score both
#   OQ_SAMPLES=256     calibration windows (x OQ_SEQLEN tokens)
#   OQ_SEQLEN=2048     window length
#   NGRAM_BITS=8       n-gram table bits (2 3 4 5 6 8)
#   PRESERVE_MTP=1     keep the MTP draft head
#   OQ_SKIP_PPL=1      skip heldout scoring
#   OQT_SCORE_ONLY=1   only (re)score an existing build
#   OQT_M3=0           skip M3 scoring (KL / top-1 / routing flips vs the BF16 source;
#                      the reference is a one-time streamed pass, cached in ~/oqup/anchors)
#   M3_FILES, M3_SEQ=2048, M3_MAX_WINDOWS=64   M3 evaluation text and windows
#   OQT_REFINE_EXPERTS=1  also run the rounding refinement (M6) on routed experts
#                      (better, but roughly 8 extra hours on Qwen3.8-Flash-Next)
#   OQT_ROUTING=0      turn off routing protection (M4)
#   OQT_ROUTING_THRESHOLD=0.02   routing mass shift that triggers more bits
#   OQT_ROUTING_MAX_LAYERS=0.25  at most this share of layers gets upgraded
#   OQT_PLUS=1         oQ-T+: threshold 0.01 and no layer cap (every drifting layer
#                      may get up to 2 more bits on the tensors feeding its router)
#   OQT_LONG_FILE=<jsonl>  whole documents for long-context windows (one {"text"} per line)
#   OQT_LONG_SHARE=0.25    share of calibration tokens in long windows
#   OQT_LONG_LEN=32768     long window length
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
OQT_REFINE_EXPERTS="${OQT_REFINE_EXPERTS:-0}"
OQT_ROUTING="${OQT_ROUTING:-1}"
if [ "${OQT_PLUS:-0}" = 1 ]; then   # oQ-T+: every drifting layer may get the extra bits
    OQT_ROUTING_THRESHOLD="${OQT_ROUTING_THRESHOLD:-0.01}"
    OQT_ROUTING_MAX_LAYERS="${OQT_ROUTING_MAX_LAYERS:-1.0}"
fi
OQT_ROUTING_THRESHOLD="${OQT_ROUTING_THRESHOLD:-0.02}"
OQT_ROUTING_MAX_LAYERS="${OQT_ROUTING_MAX_LAYERS:-0.25}"
if [ "$OQT_ROUTING" = "1" ]; then ROUTING_PY=True; else ROUTING_PY=False; fi
OQT_LONG_SHARE="${OQT_LONG_SHARE:-0.25}"
OQT_LONG_LEN="${OQT_LONG_LEN:-32768}"
LONG_PY=None
if [ -n "${OQT_LONG_FILE:-}" ] && [ -s "$OQT_LONG_FILE" ]; then LONG_PY="\"$OQT_LONG_FILE\""; fi
OQ_SEQLEN="${OQ_SEQLEN:-2048}"
NGRAM_BITS="${NGRAM_BITS:-8}"
PRESERVE_MTP="${PRESERVE_MTP:-1}"
HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"
MP="$CORPUS_REPO/scripts/model_profile.py"
mkdir -p "$OQUP" "$MODELS_OUT"

say() { printf '\n== %s ==\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
say "preflight"
[ -x "$VENV_PY" ] || die "oMLX venv python not found: $VENV_PY (set OMLX_REPO or VENV_PY)"
"$VENV_PY" -c "import omlx.oqt" 2>/dev/null \
    || die "this oMLX checkout has no oQ-T. In $OMLX_REPO run: git fetch && git checkout feat/oqt"
case " 2 3 4 5 6 8 " in *" $NGRAM_BITS "*) ;; *) die "NGRAM_BITS must be one of 2 3 4 5 6 8" ;; esac

INFO="$(python3 "$MP" info ${OQT_MODEL:+--model "$OQT_MODEL"} ${OQT_VARIANT:+--variant "$OQT_VARIANT"})" || die "no model profile"
eval "$INFO"
if [ -z "${SRC:-}" ]; then
    SRC="$(python3 "$MP" source --model "$MODEL_PROFILE" ${OQT_VARIANT:+--variant "$OQT_VARIANT"} \
        ${SOURCE_REPO:+--repo "$SOURCE_REPO"} --hub "$HUB" --search "$MODELS_OUT")" || die "no BF16 source found (see above)"
fi
python3 "$MP" check-source --model "$MODEL_PROFILE" "$SRC" \
    || die "SRC=$SRC is not a complete BF16 $MODEL_NAME ($MODEL_ARCH) checkpoint"

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
    if [ -e "$d" ] && [ "${OQT_SCORE_ONLY:-0}" != "1" ]; then
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

# ---------------------------------------------------------------- heldouts
m3_score() { # <quant-dir> <label>: KL / top-1 / routing flips vs the original BF16 model
    [ "${OQT_M3:-1}" = "1" ] || { echo "M3 scoring skipped (OQT_M3=0)"; return 0; }
    local files=() p
    for p in ${M3_FILES:-heldout-written-se.txt}; do
        [[ "$p" == /* ]] || p="$CORPUS_REPO/eval/$p"; [ -f "$p" ] && files+=("$p")
    done
    local key; key="$( { printf 'seq %s max %s\n' "${M3_SEQ:-2048}" "${M3_MAX_WINDOWS:-64}"
                       shasum -a 256 "${files[@]}" "$SRC/config.json"
                       [ -f "$SRC/model.safetensors.index.json" ] && shasum -a 256 "$SRC/model.safetensors.index.json"
                     } | shasum -a 256 | awk '{print substr($1,1,12)}')"
    local ref="$OQUP/anchors/m3-$MODEL_TAG-$key.npz"
    mkdir -p "$OQUP/anchors"
    if [ ! -f "$ref" ]; then
        say "M3 reference: streaming the BF16 source once (reused for every quant)"
        "$VENV_PY" "$CORPUS_REPO/scripts/score_vs_bf16.py" reference --src "$SRC" --files "${files[@]}" \
            --out "$ref" --seq "${M3_SEQ:-2048}" --max-windows "${M3_MAX_WINDOWS:-64}" \
            || { echo "WARNING: M3 reference failed; skipping M3 scoring" >&2; return 0; }
    fi
    local json="$OQUP/m3-$MODEL_TAG-oQ${LEVEL}-$VERSION-$2.json"
    say "M3 score: $2 vs the original model"
    "$VENV_PY" "$CORPUS_REPO/scripts/score_vs_bf16.py" score --model "$1" --reference "$ref" --json "$json" \
        || echo "WARNING: M3 scoring failed (the quant itself is fine)" >&2
    echo "compare quants: $VENV_PY $CORPUS_REPO/scripts/score_vs_bf16.py compare $OQUP/m3-$MODEL_TAG-*.json"
}

score() { # <quant-dir> <label>
    m3_score "$1" "$2"
    if [ "${OQ_SKIP_PPL:-0}" = "1" ]; then echo "heldout scoring skipped (OQ_SKIP_PPL=1)"; return 0; fi
    local files=() p
    for p in ${PPL_FILES:-heldout-written-se.txt}; do
        [[ "$p" == /* ]] || p="$CORPUS_REPO/eval/$p"; files+=("$p")
    done
    local plog="$OQUP/ppl-$MODEL_TAG-oQ${LEVEL}-$VERSION-$2.log"
    local cmd=("$VENV_PY" "$CORPUS_REPO/scripts/ppl_heldout.py" --model "$1" --files "${files[@]}"
               --chunk "${PPL_CHUNK:-2048}" --json "${plog%.log}.json")
    # Optional teacher anchors (ppl_heldout.py --teacher-save on the source); M3 covers this by default.
    [ -n "${PPL_TEACHER:-}" ] && cmd+=(--teacher "$PPL_TEACHER")
    say "heldout scores: $2 (keep the oMLX server stopped)"
    if "${cmd[@]}" > "$plog" 2>&1; then cat "$plog"; else
        echo "WARNING: scoring failed, see $plog (the quant itself is fine)" >&2; fi
}
if [ "${OQT_SCORE_ONLY:-0}" = "1" ]; then
    [ -d "$OUT" ] || die "OQT_SCORE_ONLY=1 but there is no build at $OUT"
    score "$OUT" oqt
    [ -d "$CMP_OUT" ] && score "$CMP_OUT" oqe-cmp
    exit 0
fi

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
    resume_writer=True,
    oqt_options=dict(
        refine_sweeps=1,
        refine_expert_sweeps=$OQT_REFINE_EXPERTS,
        routing_protect=$ROUTING_PY,
        routing_mass_threshold=$OQT_ROUTING_THRESHOLD,
        routing_max_layers_frac=$OQT_ROUTING_MAX_LAYERS,
        long_calib_path=$LONG_PY,
        long_seq_length=$OQT_LONG_LEN,
        long_share=$OQT_LONG_SHARE,
    ),
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

# An interrupted build leaves a writer journal: keep it so the writer resumes.
# Anything else at that path is a finished build being replaced.
if [ -e "$OUT" ] && [ ! -f "$OUT/.oq_writer_journal.json" ]; then rm -rf "$OUT"; fi
[ -f "$OUT/.oq_writer_journal.json" ] && echo "resuming the interrupted write of $OUT"
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
if "routing_mass_shift_median" in s:
    print(f"routing protection   : median routing shift {s['routing_mass_shift_median']:.3f}, "
          f"{s['routing_layers_upgraded']} layers / {s['routing_tensors_upgraded']} tensors got more bits")
if "calibration_windows" in s:
    c = s["calibration_windows"]
    print(f"calibration windows  : {c['short_windows']} x {c['short_len']} tokens"
          + (f" + {c['long_windows']} x {c['long_len']} tokens (long context)" if c["long_windows"] else " (no long windows)"))
if "expert_tiering_signal" in s:
    print(f"expert usage skew    : top 20% of experts carry {s['expert_top20pct_share_median']:.0%} "
          f"of tokens (median) -> tiering signal: {s['expert_tiering_signal']}")
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

score "$OUT" oqt
[ "${OQT_COMPARE:-0}" = "1" ] && score "$CMP_OUT" oqe-cmp

say "done: $OUT"
echo "serve it: ln -s \"$OUT\" ~/.omlx/models/  (or omlx serve --model-dir $MODELS_OUT)"
