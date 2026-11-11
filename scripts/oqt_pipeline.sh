#!/usr/bin/env bash
# oqt_pipeline.sh — corpus -> your local model's answers -> oQ-T quant, in one command.
#
#   scripts/oqt_pipeline.sh <level> <name>     run it (rerun the same command to resume)
#   scripts/oqt_pipeline.sh status <name>      where a run is
#
#   scripts/oqt_pipeline.sh 4 v1               -> ~/models-out/<Model>-oQ4t-v1
#
# Stages (each one is skipped when it already finished with the same inputs):
#   preflight  checks: oMLX branch, source model, the model that writes answers, disk, RAM
#   extract    corpus blocks -> prompts                       (offline, seconds)
#   derive     model writes the questions for knowledge cards (oMLX server)
#   seed       model writes generic and broad prompts from seeds/*.txt (oMLX server)
#   agent      model works as a coding agent on agent_tasks/ in Docker sandboxes (oMLX server)
#   generate   model answers the prompts, thinking on         (oMLX server, hours)
#   render     answers -> one calibration file in the chat template
#   build      oQ-T quant from that file                      (streamed, hours)
#   score      heldout scores
#
# Idempotent: a stage reruns only when its inputs changed (corpus, settings,
# models), and then everything after it reruns too. Resumable: an interrupted
# run continues where it stopped (answers are cached per request, the oQ-T
# sweep per layer).
#
# Options (environment variables, put them in front of the command):
#   GENERATOR=<quant dir>  model that writes the answers (default: the Qwen
#                          quant in ~/.omlx/models, else the newest oQ4/5/6
#                          quant in ~/models-out)
#   SRC=<dir>              BF16 source checkpoint (default: found in the HF cache)
#   BUDGET_TOKENS=1000000  how much text to generate (thinking included)
#   EFFORT_MIX=max=70,medium=15,low=15
#   CONCURRENCY=4          parallel requests to the server
#   OQT_PROFILE=profile    'profile' = corpus + generic + broad prompts; 'generic' = no
#                          corpus (the comparison arm). Answers are cached in
#                          ~/oqup/prep-cache, so a second run with the other profile
#                          only generates what is missing.
#   OQT_MIX=corpus=50,generic=25,broad=25   token shares per prompt group
#   PROMPTS_PER_SEED=8     prompts the model writes per seed
#   OQT_AGENT=1            agent sessions (needs Docker; skipped for OQT_PROFILE=generic)
#   AGENT_SAMPLES=2        sessions per agent task
#   OQT_LONG_SHARE=0.25    share of calibration tokens in long windows (0 = off)
#   OQT_LONG_LEN=32768     long window length in tokens
#   PORT=8765              port for the pipeline's own oMLX server
#   plus any omlx_oqt.sh option (OQ_SAMPLES, OQ_SEQLEN, NGRAM_BITS, PRESERVE_MTP, ...)
set -euo pipefail

CORPUS_REPO="$(cd "$(dirname "$0")/.." && pwd)"
OMLX_REPO="${OMLX_REPO:-$HOME/dev/omlx}"
VENV_PY="${VENV_PY:-$OMLX_REPO/.venv-3.12/bin/python}"
OQUP="${OQUP:-$HOME/oqup}"
MODELS_OUT="${MODELS_OUT:-$HOME/models-out}"
HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"
PORT="${PORT:-8765}"
BUDGET_TOKENS="${BUDGET_TOKENS:-1000000}"
EFFORT_MIX="${EFFORT_MIX:-max=70,medium=15,low=15}"
CONCURRENCY="${CONCURRENCY:-4}"
PREP="$CORPUS_REPO/scripts/prep_calibration.py"
STAGES=(preflight extract derive seed agent generate render build score)
OQT_AGENT="${OQT_AGENT:-1}"
AGENT_SAMPLES="${AGENT_SAMPLES:-2}"
OQT_LONG_SHARE="${OQT_LONG_SHARE:-0.25}"
OQT_LONG_LEN="${OQT_LONG_LEN:-32768}"
AGENT_TASKS="${OQT_AGENT_TASKS:-}"
AGENT_SANDBOX="${OQT_AGENT_SANDBOX:-docker}"
OQT_PROFILE="${OQT_PROFILE:-profile}"
OQT_MIX="${OQT_MIX:-corpus=50,generic=25,broad=25}"
PROMPTS_PER_SEED="${PROMPTS_PER_SEED:-8}"
case "$OQT_PROFILE" in profile|generic) ;; *) echo "OQT_PROFILE must be profile or generic" >&2; exit 2 ;; esac
# Seed prompts are needed only when the mix gives weight to generic or broad
# prompts (OQT_MIX=corpus=100 means corpus prompts only, and no seed stage).
NEED_SEEDS="$(python3 -c '
import sys
w = {k.strip(): float(v) for k, _, v in (p.partition("=") for p in sys.argv[1].split(",")) if v}
groups = ("generic", "broad") if sys.argv[2] == "generic" else ("corpus", "generic", "broad")
print(1 if any(w.get(g, 0) > 0 for g in ("generic", "broad") if g in groups) else 0)
' "$OQT_MIX" "$OQT_PROFILE")"
export OMLX_REPO VENV_PY OQUP MODELS_OUT

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ts() { date '+%Y-%m-%d %H:%M:%S'; }
hash_of() { shasum -a 256 | awk '{print substr($1, 1, 16)}'; }

# ----------------------------------------------------------------- status
CACHE_ROOT="$OQUP/prep-cache"
if [ "${1:-}" = "status" ]; then
    NAME="${2:-}"; [ -n "$NAME" ] || usage
    RUN="$OQUP/runs/$NAME"
    [ -d "$RUN" ] || { echo "no run named '$NAME' under $OQUP/runs"; exit 1; }
    echo "run: $RUN"
    if [ -f "$RUN/pid" ] && kill -0 "$(cat "$RUN/pid")" 2>/dev/null; then
        echo "state: RUNNING (pid $(cat "$RUN/pid"))"
    else
        echo "state: not running"
    fi
    printf '\n%-10s %-8s %-20s %s\n' stage status finished duration
    for s in "${STAGES[@]}"; do
        line="$(awk -F'\t' -v s="$s" '$1 == s' "$RUN/state.tsv" 2>/dev/null | tail -1 || true)"
        if [ -n "$line" ]; then
            IFS=$'\t' read -r _ _ when secs <<< "$line"
            printf '%-10s %-8s %-20s %dm%02ds\n' "$s" done "$when" $((secs / 60)) $((secs % 60))
        elif [ -f "$RUN/current" ] && [ "$(cut -f1 "$RUN/current")" = "$s" ]; then
            started="$(cut -f2 "$RUN/current")"
            printf '%-10s %-8s %-20s %dm so far\n' "$s" running "-" $(( ($(date +%s) - started) / 60 ))
        else
            printf '%-10s %-8s\n' "$s" "-"
        fi
    done
    if [ -f "$RUN/current" ]; then
        cur="$(cut -f1 "$RUN/current")"
        echo; echo "last lines of $cur:"; tail -n 5 "$RUN/logs/$cur.log" 2>/dev/null || true
    fi
    echo; echo "pipeline log: $RUN/pipeline.log"
    exit 0
fi

LEVEL="${1:-}"; NAME="${2:-}"
[ -n "$LEVEL" ] && [ -n "$NAME" ] || usage
case "$LEVEL" in 2|3|4|5|6|8) ;; *) echo "level must be one of 2 3 4 5 6 8" >&2; exit 2 ;; esac
case "$NAME" in */*|.*|"") echo "name must be a plain word like v1" >&2; exit 2 ;; esac

RUN="$OQUP/runs/$NAME"
mkdir -p "$RUN/logs"
PLOG="$RUN/pipeline.log"
STATE="$RUN/state.tsv"
touch "$STATE"

log() { printf '%s  %s\n' "$(ts)" "$*" | tee -a "$PLOG"; }
die() { log "FAILED: $*"; exit 1; }

if [ -f "$RUN/pid" ] && kill -0 "$(cat "$RUN/pid")" 2>/dev/null; then
    echo "run '$NAME' is already running (pid $(cat "$RUN/pid")); see: $0 status $NAME" >&2
    exit 1
fi
echo "$$" > "$RUN/pid"

SERVER_PID=""
STAGE_PID=""
kill_tree() { # <pid>: the process and all its descendants
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
    kill -TERM "$1" 2>/dev/null || true
}
stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log "stopping the pipeline's oMLX server (pid $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
        for _ in $(seq 1 60); do kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 1; done
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    SERVER_PID=""
}
on_exit() {
    rc=$?
    if [ -n "$STAGE_PID" ] && kill -0 "$STAGE_PID" 2>/dev/null; then
        log "stopping the running stage (pid $STAGE_PID)"
        kill_tree "$STAGE_PID"
        wait "$STAGE_PID" 2>/dev/null || true
    fi
    stop_server
    rm -f "$RUN/pid" "$RUN/current"
    if [ "$rc" -ne 0 ]; then
        log "stopped with exit code $rc. Rerun the same command to resume: $0 $LEVEL $NAME"
    fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM

# Timestamp every line of a stage's output into its own log.
stamp() { perl -MPOSIX -pe 'BEGIN { $| = 1 } print strftime("%Y-%m-%d %H:%M:%S  ", localtime)'; }

# summary <generate|render|oqt> <json>: one human line from a stage's JSON.
summary() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null || echo "summary unavailable"
import json, sys
kind, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
if kind == "generate":
    print("[{}] {}/{} answers kept, {:,} tokens {}, {} with tool calls, {}".format(
        d["profile"], d["kept"], d["requests"], d["tokens"], d.get("tokens_by_group", {}),
        d.get("with_tool_calls", 0), d["verdicts"]))
elif kind == "render":
    print("[{}] {} conversations ({} with tools), {} agent sessions, {} passages, {:,} tokens ({}); {} long documents (~{:,} tokens)".format(
        d["profile"], d["conversations"], d.get("with_tools", 0), d.get("agent_sessions", 0), d["passages"],
        d["tokens"], d["mode"], d.get("long_documents", 0), d.get("long_tokens_est", 0)))
elif kind == "agent":
    print("{}/{} sessions kept, {} solved by their check, {} failed to run, mean {} steps, {:,} tokens".format(
        d["kept"], d["sessions"], d["solved"], d["failed_to_run"], d["mean_steps"], d["tokens"]))
else:
    s = d.get("summary") or {}
    if s:
        print("output error x{:.2f} vs oQe (median), better on {:.0%} of {} tensors".format(
            s["median_err_ratio_oqt_vs_oqe"], s["share_tensors_improved"], s["tensors_compared"]))
    else:
        print("no comparison recorded")
PY
}

is_done() { awk -F'\t' -v s="$1" -v d="$2" '$1 == s && $2 == d { f = 1 } END { exit !f }' "$STATE"; }

# run_stage <stage> <digest> <command...>
run_stage() {
    local stage="$1" digest="$2"; shift 2
    if is_done "$stage" "$digest"; then
        log "$stage: up to date, skipped"
        return 0
    fi
    # This stage reruns, so every later stage is out of date too.
    local after=0 keep="" s
    for s in "${STAGES[@]}"; do
        [ "$s" = "$stage" ] && after=1
        [ "$after" = 0 ] && keep="$keep|$s"
    done
    awk -F'\t' -v keep="$keep|" 'index(keep, "|" $1 "|")' "$STATE" > "$STATE.tmp" || true
    mv "$STATE.tmp" "$STATE"
    printf '%s\t%s\n' "$stage" "$(date +%s)" > "$RUN/current"
    printf '\n%s  ===== %s: new attempt (inputs %s) =====\n' "$(ts)" "$stage" "$digest" >> "$RUN/logs/$stage.log"
    log "$stage: started (log: $RUN/logs/$stage.log)"
    local t0; t0=$(date +%s)
    # Background + wait: a kill reaches the trap immediately instead of after
    # the stage finishes, and the trap stops the stage's whole process tree.
    ( set -o pipefail; "$@" 2>&1 | stamp >> "$RUN/logs/$stage.log" ) &
    STAGE_PID=$!
    local rc=0
    wait "$STAGE_PID" || rc=$?
    STAGE_PID=""
    if [ "$rc" -ne 0 ]; then
        tail -n 15 "$RUN/logs/$stage.log" | sed 's/^/    /' | tee -a "$PLOG"
        die "$stage (full log: $RUN/logs/$stage.log)"
    fi
    local secs=$(( $(date +%s) - t0 ))
    printf '%s\t%s\t%s\t%s\n' "$stage" "$digest" "$(ts)" "$secs" >> "$STATE"
    rm -f "$RUN/current"
    log "$stage: done in $((secs / 60))m$(printf '%02d' $((secs % 60)))s"
}

log "=== oQ-T pipeline: oQ${LEVEL}t '$NAME' ==="

# --------------------------------------------------------------- preflight
[ -x "$VENV_PY" ] || die "oMLX venv python not found: $VENV_PY (set OMLX_REPO)"
"$VENV_PY" -c "import omlx.oqt" 2>/dev/null \
    || die "this oMLX checkout has no oQ-T. In $OMLX_REPO run: git fetch && git checkout feat/oqt"
command -v perl >/dev/null || die "perl is needed for log timestamps"

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
    [ "$n" = "1" ] || die "found $n Qwen3.8-Flash-Next source snapshots in $HUB; pass SRC=<dir>"
    SRC="$MATCHES"
fi
[ -f "$SRC/config.json" ] || die "no config.json in SRC=$SRC"
grep -q 'deepseek_v41' "$SRC/config.json" && die "oQ-T does not support DeepSeek V4.1 yet"
export SRC

is_quant_of_family() { # <dir>: a quantized qwen4_exp model dir
    [ -f "$1/config.json" ] && grep -q 'qwen4_exp' "$1/config.json" && grep -q '"quantization' "$1/config.json"
}
if [ -z "${GENERATOR:-}" ]; then
    CANDS=""
    for d in "$HOME/.omlx/models"/*; do
        [ -e "$d" ] || continue
        r="$(cd "$d" 2>/dev/null && pwd -P)" || continue
        is_quant_of_family "$r" && CANDS="$CANDS${CANDS:+$'\n'}$r"
    done
    n=0; [ -n "$CANDS" ] && n=$(printf '%s\n' "$CANDS" | sort -u | wc -l | tr -d ' ')
    if [ "$n" = "1" ]; then
        GENERATOR="$(printf '%s\n' "$CANDS" | head -1)"
    else
        for lvl in 5 6 4 8; do
            for d in $(ls -td "$MODELS_OUT"/*-oQ${lvl}e-* "$MODELS_OUT"/*-oQ${lvl}-* 2>/dev/null); do
                case "$d" in *-cmp|*oQ*t-*) continue ;; esac
                is_quant_of_family "$d" && { GENERATOR="$d"; break 2; }
            done
        done
    fi
    [ -n "${GENERATOR:-}" ] || die "no quant found to write the answers; pass GENERATOR=<quant dir>"
fi
is_quant_of_family "$GENERATOR" || die "GENERATOR=$GENERATOR is not a quantized Qwen3.8-Flash-Next dir"
GEN_ID="$(basename "$GENERATOR")"

ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
free_gb=$(df -g "$OQUP" 2>/dev/null | awk 'NR==2 {print $4}')
log "source    : $SRC"
log "answers by: $GENERATOR"
log "level     : oQ${LEVEL}t -> $MODELS_OUT/*-oQ${LEVEL}t-$NAME"
log "budget    : $BUDGET_TOKENS tokens, effort $EFFORT_MIX, concurrency $CONCURRENCY"
log "prompts   : profile $OQT_PROFILE, mix $OQT_MIX, $PROMPTS_PER_SEED prompts per seed"
[ "$OQT_PROFILE" = generic ] && OQT_AGENT=0
log "agent     : $([ "$OQT_AGENT" = 1 ] && echo "$AGENT_SAMPLES sessions per task, $AGENT_SANDBOX sandbox" || echo off)"
log "long ctx  : $(awk -v s="$OQT_LONG_SHARE" 'BEGIN{exit !(s>0)}' && echo "${OQT_LONG_SHARE} of tokens in ${OQT_LONG_LEN}-token windows" || echo off)"
if [ "$OQT_AGENT" = 1 ] && [ "$AGENT_SANDBOX" = docker ]; then
    docker info >/dev/null 2>&1 || die "agent sessions need Docker (start colima or OrbStack), or set OQT_AGENT=0"
fi
log "machine   : ${ram_gb} GB RAM, ${free_gb:-?} GB free under $OQUP"
[ "$ram_gb" -ge 96 ] || log "WARNING: ${ram_gb} GB RAM; this pipeline is planned for the 128 GB Mac"
[ -n "$free_gb" ] && [ "$free_gb" -lt 150 ] && log "WARNING: only ${free_gb} GB free"
awk -F'\t' '$1 != "preflight"' "$STATE" > "$STATE.tmp" || true
mv "$STATE.tmp" "$STATE"
printf '%s\t%s\t%s\t%s\n' preflight "-" "$(ts)" 0 >> "$STATE"

PREP_OUT="$RUN/prep"
SERVER="http://127.0.0.1:$PORT"
BUNDLE="$RUN/bundle.txt"
PREP_SHA="$(hash_of < "$PREP")"

# ----------------------------------------------------------------- digests
D_EXTRACT="$( { cat "$CORPUS_REPO"/calibration/*.txt "$CORPUS_REPO/manifest.json"; echo "$PREP_SHA"; } | hash_of)"
D_DERIVE="$(printf '%s|%s|%s' "$D_EXTRACT" "$GEN_ID" "$( { cat "$GENERATOR/config.json"; ls -l "$GENERATOR"/*.safetensors 2>/dev/null; } | hash_of)" | hash_of)"
D_SEED="$(printf '%s|%s|%s|%s' "$( cat "$CORPUS_REPO"/seeds/*.txt | hash_of)" "$PREP_SHA" "$GEN_ID" "$PROMPTS_PER_SEED" | hash_of)"
D_AGENT="$(printf '%s|%s|%s|%s|%s' "$( { find "${AGENT_TASKS:-$CORPUS_REPO/agent_tasks/tasks}" -type f -print0 | sort -z | xargs -0 cat; cat "$CORPUS_REPO/scripts/agent_harness.py"; } | hash_of)" \
    "$PREP_SHA" "$GEN_ID" "$EFFORT_MIX" "$AGENT_SAMPLES" | hash_of)"
D_GENERATE="$(printf '%s|%s|%s|%s|%s|%s|%s|%s' "$D_DERIVE" "$D_SEED" "$BUDGET_TOKENS" "$EFFORT_MIX" \
    "${MAX_TOKENS:-16384}" "$OQT_PROFILE" "$OQT_MIX" "$([ "$OQT_AGENT" = 1 ] && echo "$D_AGENT" || echo none)" | hash_of)"
D_RENDER="$(printf '%s|%s|%s' "$D_GENERATE" "$( cat "$SRC"/tokenizer*.json "$SRC"/*.jinja 2>/dev/null | hash_of)" "$OQT_LONG_LEN" | hash_of)"

# ------------------------------------------------------------------ server
start_server() {
    [ -z "$SERVER_PID" ] || return 0
    if curl -fsS -m 3 "$SERVER/health" >/dev/null 2>&1; then
        die "something already answers on port $PORT; stop it or set PORT=<free port>"
    fi
    local serve_dir="$RUN/serve-models"
    mkdir -p "$serve_dir"
    ln -sfn "$GENERATOR" "$serve_dir/$GEN_ID"
    log "starting oMLX on port $PORT with $GEN_ID (log: $RUN/logs/server.log)"
    if [ -n "${OQT_SERVE_CMD:-}" ]; then          # tests: a stand-in server
        PORT="$PORT" SERVE_DIR="$serve_dir" bash -c "$OQT_SERVE_CMD" >> "$RUN/logs/server.log" 2>&1 &
    else
        local key=(); [ -n "${OMLX_API_KEY:-}" ] && key=(--api-key "$OMLX_API_KEY")
        "$OMLX_REPO/.venv-3.12/bin/omlx" serve --model-dir "$serve_dir" --port "$PORT" "${key[@]}" \
            >> "$RUN/logs/server.log" 2>&1 &
    fi
    SERVER_PID=$!
    for i in $(seq 1 "${SERVER_WAIT:-900}"); do
        curl -fsS -m 3 "$SERVER/health" >/dev/null 2>&1 && { log "server ready after ${i}s"; return 0; }
        kill -0 "$SERVER_PID" 2>/dev/null || die "the oMLX server exited; see $RUN/logs/server.log"
        sleep 1
    done
    die "the oMLX server did not become ready; see $RUN/logs/server.log"
}

# ------------------------------------------------------------------ stages
run_stage extract "$D_EXTRACT" python3 "$PREP" extract --out "$PREP_OUT"

if ! is_done derive "$D_DERIVE" || { [ "$NEED_SEEDS" = 1 ] && ! is_done seed "$D_SEED"; } \
        || { [ "$OQT_AGENT" = 1 ] && ! is_done agent "$D_AGENT"; } || ! is_done generate "$D_GENERATE"; then
    start_server
fi
run_stage derive "$D_DERIVE" python3 "$PREP" derive --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
    --model "$GEN_ID" --server "$SERVER" --concurrency "$CONCURRENCY"
if [ "$NEED_SEEDS" = 1 ]; then
    run_stage seed "$D_SEED" python3 "$PREP" seed --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
        --model "$GEN_ID" --server "$SERVER" --concurrency "$CONCURRENCY" --prompts-per-seed "$PROMPTS_PER_SEED"
else
    log "seed: skipped (OQT_MIX gives no weight to generic or broad prompts)"
fi
if [ "$OQT_AGENT" = 1 ]; then
    agent_stage() {
        if [ "$AGENT_SANDBOX" = docker ] && [ -z "$AGENT_TASKS" ]; then
            "$CORPUS_REPO/agent_tasks/build_images.sh"
        fi
        python3 "$PREP" agent --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
            --model "$GEN_ID" --server "$SERVER" --sandbox "$AGENT_SANDBOX" \
            --agent-samples "$AGENT_SAMPLES" --effort-mix "$EFFORT_MIX" \
            ${AGENT_TASKS:+--agent-tasks "$AGENT_TASKS"}
    }
    run_stage agent "$D_AGENT" agent_stage
    [ -f "$PREP_OUT/answers/$GEN_ID/agent.json" ] && \
        log "agent: $(summary agent "$PREP_OUT/answers/$GEN_ID/agent.json")"
else
    log "agent: skipped ($([ "$OQT_PROFILE" = generic ] && echo "generic profile" || echo "OQT_AGENT=0"))"
fi
run_stage generate "$D_GENERATE" python3 "$PREP" generate --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
    --profile "$OQT_PROFILE" --mix "$OQT_MIX" \
    --model "$GEN_ID" --server "$SERVER" --concurrency "$CONCURRENCY" \
    --budget-tokens "$BUDGET_TOKENS" --effort-mix "$EFFORT_MIX" --max-tokens "${MAX_TOKENS:-16384}"
[ -f "$PREP_OUT/answers/$GEN_ID/generate-$OQT_PROFILE.json" ] && \
    log "generate: $(summary generate "$PREP_OUT/answers/$GEN_ID/generate-$OQT_PROFILE.json")"
stop_server

run_stage render "$D_RENDER" "$VENV_PY" "$PREP" render --out "$PREP_OUT" --profile "$OQT_PROFILE" \
    --model "$GEN_ID" --source "$SRC" --bundle "$BUNDLE" \
    --long-len "$OQT_LONG_LEN" --long-bundle "$RUN/bundle-long.jsonl" \
    $([ "$OQT_AGENT" = 1 ] || echo --no-agent)

# The build needs the memory: no other oMLX server may be running.
if pgrep -f "omlx.*serve" >/dev/null 2>&1 && [ "${OQT_IGNORE_SERVER:-0}" != "1" ]; then
    die "an oMLX server is running; stop it before the build (it needs the memory), then rerun"
fi
OMLX_COMMIT="$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
D_BUILD="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' "$(hash_of < "$BUNDLE")" "$LEVEL" "${OQ_SAMPLES:-256}" \
    "${OQ_SEQLEN:-2048}" "${NGRAM_BITS:-8}" "${PRESERVE_MTP:-1}" "$OMLX_COMMIT" \
    "$(hash_of < "$CORPUS_REPO/scripts/omlx_oqt.sh")" \
    "${OQT_REFINE_EXPERTS:-0}/${OQT_ROUTING:-1}/${OQT_ROUTING_THRESHOLD:-0.02}/${OQT_ROUTING_MAX_LAYERS:-0.25}" \
    "$OQT_LONG_SHARE/$OQT_LONG_LEN/$( hash_of < "$RUN/bundle-long.jsonl" 2>/dev/null || echo none)" | hash_of)"
run_stage build "$D_BUILD" env CORPUS_FILE="$BUNDLE" OQT_OVERWRITE=1 OQ_SKIP_PPL=1 OQT_M3=0 \
    OQT_LONG_FILE="$RUN/bundle-long.jsonl" OQT_LONG_SHARE="$OQT_LONG_SHARE" OQT_LONG_LEN="$OQT_LONG_LEN" \
    "$CORPUS_REPO/scripts/omlx_oqt.sh" "$LEVEL" "$NAME"

D_SCORE="$(printf '%s|%s|%s|%s' "$D_BUILD" "$(cat "$CORPUS_REPO"/eval/heldout-*.txt | hash_of)" \
    "${OQ_SKIP_PPL:-0}/${OQT_M3:-1}/${M3_SEQ:-2048}/${M3_MAX_WINDOWS:-64}" "$(hash_of < "$CORPUS_REPO/scripts/score_vs_bf16.py")" | hash_of)"
if [ "${OQ_SKIP_PPL:-0}" = "1" ] && [ "${OQT_M3:-1}" = "0" ]; then
    log "score: skipped (OQ_SKIP_PPL=1 and OQT_M3=0)"
else
    run_stage score "$D_SCORE" env OQT_SCORE_ONLY=1 "$CORPUS_REPO/scripts/omlx_oqt.sh" "$LEVEL" "$NAME"
fi

# ----------------------------------------------------------------- summary
OUT="$(ls -d "$MODELS_OUT"/*-oQ${LEVEL}t-"$NAME" 2>/dev/null | head -1)"
log "=== done ==="
log "quant     : $OUT"
if [ -n "$OUT" ] && [ -f "$OUT/oqt_report.json" ]; then
    log "oQ-T      : $(summary oqt "$OUT/oqt_report.json")"
fi
[ -f "$PREP_OUT/answers/$GEN_ID/render-$OQT_PROFILE.json" ] && \
    log "calibration: $(summary render "$PREP_OUT/answers/$GEN_ID/render-$OQT_PROFILE.json")"
log "serve it  : ln -s \"$OUT\" ~/.omlx/models/"
