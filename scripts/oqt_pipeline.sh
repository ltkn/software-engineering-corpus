#!/usr/bin/env bash
# oqt_pipeline.sh — corpus -> your local model's answers -> oQ-T quant, in one command.
#
#   scripts/oqt_pipeline.sh <level> <name>     run it (rerun the same command to resume)
#   scripts/oqt_pipeline.sh status <name>      where a run is
#   scripts/oqt_pipeline.sh results            every run's scores side by side
#   scripts/oqt_pipeline.sh compare v1 v1-plus two runs metric by metric, with a verdict
#   scripts/oqt_pipeline.sh bench              how fast the generator writes, per MTP setting
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
#   agent-eval the quant works the agent tasks; solve rate vs the generator's
#              (only with OQT_AGENT_EVAL=1; needs Docker again)
#
# Idempotent: a stage reruns only when its inputs changed (corpus, settings,
# models), and then everything after it reruns too. Resumable: an interrupted
# run continues where it stopped (answers are cached per request, the oQ-T
# sweep per layer).
#
# Options (environment variables, put them in front of the command):
#   OQT_MODEL=<id>         model profile in models/<id>.json (default: the only one;
#                          scripts/model_profile.py list shows them)
#   OQT_VARIANT=<suffix>   a fine-tune named <name>-<suffix>, e.g. uncensored ->
#                          Qwen3.8-Flash-Next-uncensored: its BF16 source is the
#                          folder of that name in ~/models-out (or an HF repo
#                          <org>/<that name>), its answers come from a quant named
#                          <that name>-oQ<level>...
#   GENERATOR=<quant dir>  model that writes the answers (default: the one quant
#                          of the model in ~/.omlx/models, else the newest oQ5,
#                          oQ6, oQ4 or oQ8 quant named <name>[-<variant>]-oQ... in
#                          ~/models-out, in that order)
#   SRC=<dir>              BF16 source checkpoint (default: the newest complete,
#                          unquantized snapshot of the profile's official repo in
#                          the HF cache; fine-tunes are never picked by accident)
#   SOURCE_REPO=<org/name> quantize a fine-tune from this HF repo instead, e.g.
#                          orcarouter/Qwen3.8-Flash-Next-Uncensored (then GENERATOR
#                          must be a quant of that fine-tune)
#   OQT_PLUS=1             oQ-T+: every layer whose expert routing drifts gets more
#                          bits on the tensors that feed its router (no 25% cap,
#                          lower threshold); a little larger, closer to the original
#   OQT_MTP=off|auto|<1-8> how oMLX drafts tokens with the model's MTP head while
#                          generating (speed only, same answers; not saved; default:
#                          the model's own oMLX setting). Measure with: bench
#   OQT_KEEP_BUILD=1       keep the existing quant if it was built from this exact
#                          bundle (after an update of these scripts; not saved)
#   OQT_AGENT_EVAL=1       after the score, run the agent tasks with the quant
#                          (Docker needed; not saved with the run, add it to a
#                          finished run's command to evaluate it)
#   BUDGET_TOKENS=1000000  how much text to generate (thinking included)
#   EFFORT_MIX=max=70,medium=15,low=15
#   CONCURRENCY=1          parallel requests to the server (1: one request at a
#                          time, least memory; try 2 if the Mac has headroom)
#   AGENT_CONCURRENCY      parallel agent sessions (default: CONCURRENCY)
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
#   OQT_HOLDOUT_SHARE=0.05 share of prompts and agent tasks kept out of the calibration:
#                          the model's answers to them are what M3 scores the quant on
#   PORT=8765              port for the pipeline's own oMLX server
#   plus any omlx_oqt.sh option (OQ_SAMPLES, OQ_SEQLEN, NGRAM_BITS, PRESERVE_MTP, ...)
set -euo pipefail

CORPUS_REPO="$(cd "$(dirname "$0")/.." && pwd)"
OMLX_REPO="${OMLX_REPO:-$HOME/dev/omlx}"
VENV_PY="${VENV_PY:-$OMLX_REPO/.venv-3.12/bin/python}"
OQUP="${OQUP:-$HOME/oqup}"
MODELS_OUT="${MODELS_OUT:-$HOME/models-out}"
HUB="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"
MP="$CORPUS_REPO/scripts/model_profile.py"

# A run's settings are saved on its first start (runs/<name>/settings.env) and
# reused on every resume, so "scripts/oqt_pipeline.sh 4 v1" alone continues the
# same run with the same generator and budget. A setting given again with a
# different value stops the run, unless OQT_CHANGE_SETTINGS=1 (the new value is
# saved, and the stages it affects rerun). Speed-only knobs (CONCURRENCY, PORT,
# the sandbox kind) are not saved and can change freely.
SETTINGS=(OQT_MODEL OQT_VARIANT GENERATOR SRC SOURCE_REPO BUDGET_TOKENS EFFORT_MIX MAX_TOKENS OQT_PROFILE OQT_MIX
          PROMPTS_PER_SEED OQT_AGENT AGENT_SAMPLES OQT_AGENT_TASKS OQT_LONG_SHARE OQT_LONG_LEN OQT_HOLDOUT_SHARE
          OQ_SAMPLES OQ_SEQLEN NGRAM_BITS PRESERVE_MTP OQT_REFINE_EXPERTS OQT_ROUTING
          OQT_ROUTING_THRESHOLD OQT_ROUTING_MAX_LAYERS OQT_PLUS)
setting_norm() { # <name> <value>: paths compare by their real location
    case "$1" in
        GENERATOR|SRC|OQT_AGENT_TASKS) [ -n "$2" ] && (cd "$2" 2>/dev/null && pwd -P) || printf '%s\n' "$2" ;;
        *) printf '%s\n' "$2" ;;
    esac
}
SETTINGS_FILE=""; SETTINGS_CHANGED=""
if [ "${1:-}" != status ] && [ "${1:-}" != bench ] && [ -n "${2:-}" ]; then
    SETTINGS_FILE="$OQUP/runs/$2/settings.env"
    if [ -f "$SETTINGS_FILE" ]; then
        while IFS='=' read -r k v; do
            case " ${SETTINGS[*]} " in *" $k "*) ;; *) continue ;; esac
            if [ -n "${!k:-}" ]; then
                [ "$(setting_norm "$k" "${!k}")" = "$(setting_norm "$k" "$v")" ] \
                    || SETTINGS_CHANGED="$SETTINGS_CHANGED"$'\n'"  $k: saved '$v', given '${!k}'"
            elif [ -n "$v" ]; then
                printf -v "$k" '%s' "$v"
                export "${k?}"
            fi
        done < "$SETTINGS_FILE"
    fi
fi
# oQ-T+ is a routing-protection preset: no cap on the layers that get more bits and
# a lower threshold. Explicit OQT_ROUTING_* values still win.
OQT_PLUS="${OQT_PLUS:-0}"
if [ "$OQT_PLUS" = 1 ]; then
    OQT_ROUTING_THRESHOLD="${OQT_ROUTING_THRESHOLD:-0.01}"
    OQT_ROUTING_MAX_LAYERS="${OQT_ROUTING_MAX_LAYERS:-1.0}"
    export OQT_ROUTING_THRESHOLD OQT_ROUTING_MAX_LAYERS
fi
save_settings() {
    [ -n "$SETTINGS_FILE" ] || return 0
    local k tmp="$SETTINGS_FILE.tmp"
    for k in "${SETTINGS[@]}"; do
        case "$k" in   # the defaults the stages use, so a resume compares like with like
            MAX_TOKENS) printf '%s=%s\n' "$k" "${MAX_TOKENS:-16384}" ;;
            OQ_SAMPLES) printf '%s=%s\n' "$k" "${OQ_SAMPLES:-256}" ;;
            OQ_SEQLEN) printf '%s=%s\n' "$k" "${OQ_SEQLEN:-2048}" ;;
            NGRAM_BITS) printf '%s=%s\n' "$k" "${NGRAM_BITS:-8}" ;;
            PRESERVE_MTP) printf '%s=%s\n' "$k" "${PRESERVE_MTP:-1}" ;;
            OQT_REFINE_EXPERTS) printf '%s=%s\n' "$k" "${OQT_REFINE_EXPERTS:-0}" ;;
            OQT_ROUTING) printf '%s=%s\n' "$k" "${OQT_ROUTING:-1}" ;;
            OQT_ROUTING_THRESHOLD) printf '%s=%s\n' "$k" "${OQT_ROUTING_THRESHOLD:-0.02}" ;;
            OQT_ROUTING_MAX_LAYERS) printf '%s=%s\n' "$k" "${OQT_ROUTING_MAX_LAYERS:-0.25}" ;;
            *) printf '%s=%s\n' "$k" "${!k:-}" ;;
        esac
    done > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
}
PORT="${PORT:-8765}"
BUDGET_TOKENS="${BUDGET_TOKENS:-1000000}"
EFFORT_MIX="${EFFORT_MIX:-max=70,medium=15,low=15}"
CONCURRENCY="${CONCURRENCY:-1}"
AGENT_CONCURRENCY="${AGENT_CONCURRENCY:-$CONCURRENCY}"
PREP="$CORPUS_REPO/scripts/prep_calibration.py"
STAGES=(preflight extract derive seed agent generate render build score agent-eval)
OQT_AGENT="${OQT_AGENT:-1}"
AGENT_SAMPLES="${AGENT_SAMPLES:-2}"
OQT_LONG_SHARE="${OQT_LONG_SHARE:-0.25}"
OQT_LONG_LEN="${OQT_LONG_LEN:-32768}"
OQT_HOLDOUT_SHARE="${OQT_HOLDOUT_SHARE:-0.05}"
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

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ts() { date '+%Y-%m-%d %H:%M:%S'; }
hash_of() { shasum -a 256 | awk '{print substr($1, 1, 16)}'; }

# ----------------------------------------------------------------- status
CACHE_ROOT="$OQUP/prep-cache"
if [ "${1:-}" = "results" ]; then
    exec python3 "$CORPUS_REPO/scripts/results.py" table --oqup "$OQUP"
fi
if [ "${1:-}" = "compare" ]; then
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage: $0 compare <run> <other run>" >&2; exit 2; }
    exec python3 "$CORPUS_REPO/scripts/results.py" compare "$2" "$3" --oqup "$OQUP"
fi
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
    if [ -f "$RUN/settings.env" ]; then
        echo; echo "settings (reused on resume):"
        grep -E '^(OQT_MODEL|OQT_VARIANT|GENERATOR|SRC|SOURCE_REPO|BUDGET_TOKENS|EFFORT_MIX|OQT_PROFILE|OQT_MIX)=.' "$RUN/settings.env" | sed 's/^/  /'
    fi
    echo; echo "pipeline log: $RUN/pipeline.log"
    exit 0
fi

LEVEL="${1:-}"; NAME="${2:-}"
BENCH=0
if [ "$LEVEL" = bench ]; then BENCH=1; NAME=bench; fi
[ -n "$LEVEL" ] && [ -n "$NAME" ] || usage
case "$LEVEL" in 2|3|4|5|6|8|bench) ;; *) echo "level must be one of 2 3 4 5 6 8" >&2; exit 2 ;; esac
case "$NAME" in */*|.*|"") echo "name must be a plain word like v1" >&2; exit 2 ;; esac

RUN="$OQUP/runs/$NAME"
mkdir -p "$RUN/logs"
PLOG="$RUN/pipeline.log"
STATE="$RUN/state.tsv"
touch "$STATE"

log() { printf '%s  %s\n' "$(ts)" "$*" | tee -a "$PLOG"; }
die() { log "FAILED: $*"; exit 1; }

if [ -n "$SETTINGS_CHANGED" ]; then
    if [ "${OQT_CHANGE_SETTINGS:-0}" = 1 ]; then
        log "settings changed on purpose (OQT_CHANGE_SETTINGS=1):$SETTINGS_CHANGED"
    else
        die "run '$NAME' was started with other settings:$SETTINGS_CHANGED
To resume it as it was, leave these out: $0 $LEVEL $NAME
To change them on purpose, add OQT_CHANGE_SETTINGS=1 (the affected stages rerun), or use a new run name."
    fi
fi

# Docker's own CPUs, memory and disk (with colima these are the VM's, not the Mac's).
# Fails when the agent sandboxes cannot work; warns when they will be slow or tight.
docker_check() {
    local cpus mem_mb mem_gb missing=0 need_gb disk_gb fix
    cpus="$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)"
    mem_mb=$(( $(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0) / 1048576 ))
    mem_gb="$(awk -v m="$mem_mb" 'BEGIN{printf "%.1f", m / 1024}')"
    for img in "$CORPUS_REPO"/agent_tasks/images/*/; do
        docker image inspect "oqt-agent-$(basename "$img")" >/dev/null 2>&1 || missing=$((missing + 1))
    done
    # Building every image needs about 25 GB plus build cache; running only needs scratch space.
    need_gb=10; [ "$missing" -gt 0 ] && need_gb=40
    disk_gb="$(docker run --rm --network none debian:trixie-slim df -Pk / 2>/dev/null | awk 'NR==2 {print int($4 / 1048576)}')"
    fix="with colima: colima stop && colima start --cpu 4 --memory 8 --disk 120 (the disk can only grow); with OrbStack: Settings > System"
    log "docker    : ${cpus} CPUs, ${mem_gb} GB memory, ${disk_gb:-?} GB free disk, ${missing} sandbox images to build"
    # Each sandbox is capped at 2 GB; the VM needs room for itself too.
    [ "$mem_mb" -ge 3000 ] || die "Docker has ${mem_gb} GB memory; the agent sandboxes need at least 3 (8 recommended). Fix $fix"
    [ -z "$disk_gb" ] || [ "$disk_gb" -ge "$need_gb" ] \
        || die "Docker has ${disk_gb} GB free disk; need ${need_gb} GB. Free space with docker system prune, or fix $fix"
    [ "$mem_mb" -ge 7000 ] || log "WARNING: Docker has ${mem_gb} GB memory; 8 is recommended. $fix"
    [ "$cpus" -ge 4 ] || log "WARNING: Docker has ${cpus} CPUs; firmware builds will be slow. 4 recommended. $fix"
}

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
        log "stopped with exit code $rc. To resume: $0 $LEVEL $NAME (its settings are kept in $SETTINGS_FILE)"
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

if [ "$BENCH" = 1 ]; then log "=== oQ-T pipeline: generation speed bench ==="
else log "=== oQ-T pipeline: oQ${LEVEL}t$([ "$OQT_PLUS" = 1 ] && echo +) '$NAME' ==="; fi

# --------------------------------------------------------------- preflight
[ -x "$VENV_PY" ] || die "oMLX venv python not found: $VENV_PY (set OMLX_REPO)"
"$VENV_PY" -c "import omlx.oqt" 2>/dev/null \
    || die "this oMLX checkout has no oQ-T. In $OMLX_REPO run: git fetch && git checkout feat/oqt"
command -v perl >/dev/null || die "perl is needed for log timestamps"

# The model profile (models/<id>.json) and, for a fine-tune, its variant suffix.
# mp <command> ...: model_profile.py with its explanations in the pipeline log.
mp() {
    local why rc=0 outp
    why="$(mktemp)"
    outp="$(python3 "$MP" "$@" 2>"$why")" || rc=$?
    while IFS= read -r l; do log "$l" >&2; done < "$why"
    rm -f "$why"
    [ "$rc" = 0 ] && printf '%s\n' "$outp"
    return "$rc"
}
INFO="$(mp info ${OQT_MODEL:+--model "$OQT_MODEL"} ${OQT_VARIANT:+--variant "$OQT_VARIANT"})" || die "no model profile"
eval "$INFO"
OQT_MODEL="${OQT_MODEL:-$MODEL_ID}"; OQT_VARIANT="${OQT_VARIANT:-}"
export OQT_MODEL OQT_VARIANT

if [ -z "${SRC:-}" ]; then
    SRC="$(mp source --model "$MODEL_PROFILE" ${OQT_VARIANT:+--variant "$OQT_VARIANT"} \
        ${SOURCE_REPO:+--repo "$SOURCE_REPO"} --hub "$HUB" --search "$MODELS_OUT")" || die "no BF16 source found"
fi
mp check-source --model "$MODEL_PROFILE" "$SRC" >/dev/null \
    || die "SRC=$SRC is not a complete BF16 $MODEL_NAME ($MODEL_ARCH) checkpoint"
export SRC

# The answers must come from the model being quantized. The official source and a
# named variant have a naming rule for their quants (<name>[-<variant>]-oQ...); any
# other source (SRC=, SOURCE_REPO=) needs the generator named explicitly.
case "$SRC" in
    */models--"${MODEL_REPO//\//--}"/snapshots/*) ;;
    *) [ -n "${GENERATOR:-}" ] || [ -n "$OQT_VARIANT" ] \
        || die "source is not the official $MODEL_REPO ($SRC): pass GENERATOR=<a quant of this same model> so the answers come from it, or name the fine-tune with OQT_VARIANT=<suffix>" ;;
esac
if [ -z "${GENERATOR:-}" ]; then
    GENERATOR="$(mp generator --model "$MODEL_PROFILE" ${OQT_VARIANT:+--variant "$OQT_VARIANT"} \
        --search "$MODELS_OUT" --candidates "$HOME/.omlx/models"/*)" || die "no quant found to write the answers"
fi
mp check-quant --model "$MODEL_PROFILE" "$GENERATOR" >/dev/null \
    || die "GENERATOR=$GENERATOR is not a quantized $MODEL_NAME"
case "$SRC" in
    *models--*) _t="${SRC%%/snapshots/*}"; SRC_TAG="${_t##*--}" ;;
    *) SRC_TAG="$(basename "$SRC")" ;;
esac
case "$(basename "$GENERATOR" | tr '[:upper:]' '[:lower:]')" in
    "$(printf '%s' "$SRC_TAG" | tr '[:upper:]' '[:lower:]')"-oq*) ;;
    *) log "WARNING: GENERATOR $(basename "$GENERATOR") is not named like a quant of $SRC_TAG ($SRC_TAG-oQ...); make sure its answers come from the model being quantized" ;;
esac
GEN_ID="$(basename "$GENERATOR")"
save_settings

ram_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
free_gb=$(df -g "$OQUP" 2>/dev/null | awk 'NR==2 {print $4}')
log "model     : $MODEL_NAME${OQT_VARIANT:+, variant $OQT_VARIANT} (profile $MODEL_PROFILE)"
log "source    : $SRC"
log "answers by: $GENERATOR"
[ "$BENCH" = 1 ] || log "level     : oQ${LEVEL}t$([ "$OQT_PLUS" = 1 ] && echo "+ (routing protection on every drifting layer)") -> $MODELS_OUT/*-oQ${LEVEL}t-$NAME"
log "budget    : $BUDGET_TOKENS tokens, effort $EFFORT_MIX, concurrency $CONCURRENCY"
log "prompts   : profile $OQT_PROFILE, mix $OQT_MIX, $PROMPTS_PER_SEED prompts per seed"
[ "$OQT_PROFILE" = generic ] && OQT_AGENT=0
log "agent     : $([ "$OQT_AGENT" = 1 ] && echo "$AGENT_SAMPLES sessions per task, $AGENT_CONCURRENCY at a time, $AGENT_SANDBOX sandbox" || echo off)"
log "long ctx  : $(awk -v s="$OQT_LONG_SHARE" 'BEGIN{exit !(s>0)}' && echo "${OQT_LONG_SHARE} of tokens in ${OQT_LONG_LEN}-token windows" || echo off)"
log "machine   : ${ram_gb} GB RAM, ${free_gb:-?} GB free under $OQUP"
[ "$ram_gb" -ge 96 ] || log "WARNING: ${ram_gb} GB RAM; this pipeline is planned for the 128 GB Mac"
[ -n "$free_gb" ] && [ "$free_gb" -lt 150 ] && log "WARNING: only ${free_gb} GB free"
awk -F'\t' '$1 != "preflight"' "$STATE" > "$STATE.tmp" || true
mv "$STATE.tmp" "$STATE"
# The chat template must take the conversations the pipeline renders (thinking,
# tool calls): checked now, in seconds, rather than after hours of generation.
"$VENV_PY" "$CORPUS_REPO/scripts/prep_calibration.py" check --source "$SRC" --model-profile "$MODEL_PROFILE" \
    > "$RUN/logs/check.log" 2>&1 || { sed 's/^/    /' "$RUN/logs/check.log" | tee -a "$PLOG"; die "the source's chat template does not fit profile $MODEL_ID"; }
log "template  : $(tail -1 "$RUN/logs/check.log")"
printf '%s\t%s\t%s\t%s\n' preflight "-" "$(ts)" 0 >> "$STATE"

PREP_OUT="$RUN/prep"
SERVER="http://127.0.0.1:$PORT"
BUNDLE="$RUN/bundle.txt"
# Request settings live in the model profile: editing it reruns the request stages.
PREP_SHA="$(cat "$PREP" "$MP" "$MODEL_PROFILE" | hash_of)"
PM=(--model-profile "$MODEL_PROFILE")

# ----------------------------------------------------------------- digests
D_EXTRACT="$( { cat "$CORPUS_REPO"/calibration/*.txt "$CORPUS_REPO/manifest.json"; echo "$PREP_SHA"; } | hash_of)"
D_DERIVE="$(printf '%s|%s|%s' "$D_EXTRACT" "$GEN_ID" "$( { cat "$GENERATOR/config.json"; ls -l "$GENERATOR"/*.safetensors 2>/dev/null; } | hash_of)" | hash_of)"
D_SEED="$(printf '%s|%s|%s|%s' "$( cat "$CORPUS_REPO"/seeds/*.txt | hash_of)" "$PREP_SHA" "$GEN_ID" "$PROMPTS_PER_SEED" | hash_of)"
D_AGENT="$(printf '%s|%s|%s|%s|%s' "$( { find "${AGENT_TASKS:-$CORPUS_REPO/agent_tasks/tasks}" -type f -print0 | sort -z | xargs -0 cat; cat "$CORPUS_REPO/scripts/agent_harness.py"; } | hash_of)" \
    "$PREP_SHA" "$GEN_ID" "$EFFORT_MIX" "$AGENT_SAMPLES" | hash_of)"
D_GENERATE="$(printf '%s|%s|%s|%s|%s|%s|%s|%s' "$D_DERIVE" "$D_SEED" "$BUDGET_TOKENS" "$EFFORT_MIX" \
    "${MAX_TOKENS:-16384}" "$OQT_PROFILE" "$OQT_MIX" "$([ "$OQT_AGENT" = 1 ] && echo "$D_AGENT" || echo none)" | hash_of)"
D_RENDER="$(printf '%s|%s|%s|%s' "$D_GENERATE" "$( cat "$SRC"/tokenizer*.json "$SRC"/*.jinja 2>/dev/null | hash_of)" "$OQT_LONG_LEN" "$OQT_HOLDOUT_SHARE" | hash_of)"

# Docker is needed only while agent sessions still have to run: once the agent
# stage is done (or cached), the run can resume with Docker stopped, which frees
# its VM's memory for the build.
# agent_args <out dir> <cache root> <served model>: the agent stage's arguments.
agent_args() {
    printf '%s\0' agent --out "$1" --cache-root "$2" --model "$3" "${PM[@]}" --server "$SERVER" \
        --sandbox "$AGENT_SANDBOX" --agent-samples "$AGENT_SAMPLES" --effort-mix "$EFFORT_MIX" \
        --agent-concurrency "$AGENT_CONCURRENCY" ${AGENT_TASKS:+--agent-tasks "$AGENT_TASKS"}
}
# agent_cached <out> <cache root> <model>: every session already in the cache (no Docker needed).
agent_cached() {
    local a=(); while IFS= read -r -d '' x; do a+=("$x"); done < <(agent_args "$@")
    python3 "$PREP" "${a[@]}" --check-cache >/dev/null 2>&1
}
AGENT_ALL_CACHED=0
if [ "$BENCH" = 1 ]; then
    :
elif [ "$OQT_AGENT" = 1 ] && [ "$AGENT_SANDBOX" = docker ] && ! is_done agent "$D_AGENT" \
        && agent_cached "$PREP_OUT" "$CACHE_ROOT" "$GEN_ID"; then
    AGENT_ALL_CACHED=1
    log "docker    : not needed (every agent session is already cached)"
elif [ "$OQT_AGENT" = 1 ] && [ "$AGENT_SANDBOX" = docker ] && ! is_done agent "$D_AGENT"; then
    docker info >/dev/null 2>&1 || die "agent sessions need Docker (start colima or OrbStack), or set OQT_AGENT=0"
    docker_check
elif [ "$OQT_AGENT" = 1 ] && [ "$AGENT_SANDBOX" = docker ]; then
    log "docker    : not needed (agent stage done); you can stop colima to free memory for the build"
fi

# ------------------------------------------------------------------ server
BENCH_PY="$CORPUS_REPO/scripts/bench_generate.py"
# mtp_setup <model id>: apply OQT_MTP (before the model loads, so no reload), then log
# the setting the model is served with. Speed only: answers are the same.
mtp_setup() {
    if [ -n "${OQT_MTP:-}" ]; then
        python3 "$BENCH_PY" apply "$OQT_MTP" --server "$SERVER" --model "$1" >/dev/null 2>"$RUN/logs/mtp.err" \
            || die "could not set MTP $OQT_MTP: $(cat "$RUN/logs/mtp.err")"
    fi
    log "decoding  : $(python3 "$BENCH_PY" show --server "$SERVER" --model "$1" 2>&1 | tail -1)"
}
start_server() { # [model dir]: serves GENERATOR unless another model is given
    local model="${1:-$GENERATOR}" id
    id="$(basename "$model")"
    [ -z "$SERVER_PID" ] || return 0
    if curl -fsS -m 3 "$SERVER/health" >/dev/null 2>&1; then
        die "something already answers on port $PORT; stop it or set PORT=<free port>"
    fi
    local serve_dir="$RUN/serve-models"
    rm -rf "$serve_dir"; mkdir -p "$serve_dir"
    ln -sfn "$model" "$serve_dir/$id"
    log "starting oMLX on port $PORT with $id (log: $RUN/logs/server.log)"
    if [ -n "${OQT_SERVE_CMD:-}" ]; then          # tests: a stand-in server
        PORT="$PORT" SERVE_DIR="$serve_dir" bash -c "$OQT_SERVE_CMD" >> "$RUN/logs/server.log" 2>&1 &
    else
        local key=(); [ -n "${OMLX_API_KEY:-}" ] && key=(--api-key "$OMLX_API_KEY")
        "$OMLX_REPO/.venv-3.12/bin/omlx" serve --model-dir "$serve_dir" --port "$PORT" "${key[@]}" \
            >> "$RUN/logs/server.log" 2>&1 &
    fi
    SERVER_PID=$!
    for i in $(seq 1 "${SERVER_WAIT:-900}"); do
        curl -fsS -m 3 "$SERVER/health" >/dev/null 2>&1 && { log "server ready after ${i}s"; mtp_setup "$id"; return 0; }
        kill -0 "$SERVER_PID" 2>/dev/null || die "the oMLX server exited; see $RUN/logs/server.log"
        sleep 1
    done
    die "the oMLX server did not become ready; see $RUN/logs/server.log"
}

# ------------------------------------------------------------------- bench
if [ "$BENCH" = 1 ]; then
    start_server
    python3 "$BENCH_PY" bench --server "$SERVER" --model "$GEN_ID" "${PM[@]}" --json "$RUN/bench.json" \
        2>&1 | tee -a "$PLOG"
    exit "${PIPESTATUS[0]}"
fi

# ------------------------------------------------------------------ stages
run_stage extract "$D_EXTRACT" python3 "$PREP" extract --out "$PREP_OUT"

if ! is_done derive "$D_DERIVE" || { [ "$NEED_SEEDS" = 1 ] && ! is_done seed "$D_SEED"; } \
        || { [ "$OQT_AGENT" = 1 ] && ! is_done agent "$D_AGENT"; } || ! is_done generate "$D_GENERATE"; then
    start_server
fi
run_stage derive "$D_DERIVE" python3 "$PREP" derive --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
    --model "$GEN_ID" "${PM[@]}" --server "$SERVER" --concurrency "$CONCURRENCY"
if [ "$NEED_SEEDS" = 1 ]; then
    run_stage seed "$D_SEED" python3 "$PREP" seed --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
        --model "$GEN_ID" "${PM[@]}" --server "$SERVER" --concurrency "$CONCURRENCY" --prompts-per-seed "$PROMPTS_PER_SEED"
else
    log "seed: skipped (OQT_MIX gives no weight to generic or broad prompts)"
fi
# agent_sessions <out dir> <cache root> <served model>: every agent task, AGENT_SAMPLES times.
agent_sessions() {
    if [ "$AGENT_SANDBOX" = docker ] && [ -z "$AGENT_TASKS" ] && ! agent_cached "$@"; then
        "$CORPUS_REPO/agent_tasks/build_images.sh"
    fi
    local a=(); while IFS= read -r -d '' x; do a+=("$x"); done < <(agent_args "$@")
    python3 "$PREP" "${a[@]}"
}
if [ "$OQT_AGENT" = 1 ]; then
    run_stage agent "$D_AGENT" agent_sessions "$PREP_OUT" "$CACHE_ROOT" "$GEN_ID"
    [ -f "$PREP_OUT/answers/$GEN_ID/agent.json" ] && \
        log "agent: $(summary agent "$PREP_OUT/answers/$GEN_ID/agent.json")"
else
    log "agent: skipped ($([ "$OQT_PROFILE" = generic ] && echo "generic profile" || echo "OQT_AGENT=0"))"
fi
run_stage generate "$D_GENERATE" python3 "$PREP" generate --out "$PREP_OUT" --cache-root "$CACHE_ROOT" \
    --profile "$OQT_PROFILE" --mix "$OQT_MIX" \
    --model "$GEN_ID" "${PM[@]}" --server "$SERVER" --concurrency "$CONCURRENCY" \
    --budget-tokens "$BUDGET_TOKENS" --effort-mix "$EFFORT_MIX" --max-tokens "${MAX_TOKENS:-16384}"
[ -f "$PREP_OUT/answers/$GEN_ID/generate-$OQT_PROFILE.json" ] && \
    log "generate: $(summary generate "$PREP_OUT/answers/$GEN_ID/generate-$OQT_PROFILE.json")"
stop_server

run_stage render "$D_RENDER" "$VENV_PY" "$PREP" render --out "$PREP_OUT" --profile "$OQT_PROFILE" \
    --model "$GEN_ID" "${PM[@]}" --source "$SRC" --bundle "$BUNDLE" \
    --long-len "$OQT_LONG_LEN" --long-bundle "$RUN/bundle-long.jsonl" \
    --holdout-share "$OQT_HOLDOUT_SHARE" --heldout-dir "$RUN/heldout" \
    $([ "$OQT_AGENT" = 1 ] || echo --no-agent)

OUT="$MODELS_OUT/$SRC_TAG-oQ${LEVEL}t-$NAME"   # omlx_oqt.sh names it the same way
QUANT_ID="$(basename "$OUT")"

# The build needs the memory: no other oMLX server may be running.
if pgrep -f "omlx.*serve" >/dev/null 2>&1 && [ "${OQT_IGNORE_SERVER:-0}" != "1" ]; then
    die "an oMLX server is running; stop it before the build (it needs the memory), then rerun"
fi
OMLX_COMMIT="$(git -C "$OMLX_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
D_BUILD="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' "$(hash_of < "$BUNDLE")" "$LEVEL" "${OQ_SAMPLES:-256}" \
    "${OQ_SEQLEN:-2048}" "${NGRAM_BITS:-8}" "${PRESERVE_MTP:-1}" "$OMLX_COMMIT" \
    "$(awk '/^write_runner\(\) \{/,/^}$/' "$CORPUS_REPO/scripts/omlx_oqt.sh" | hash_of)" \
    "${OQT_REFINE_EXPERTS:-0}/${OQT_ROUTING:-1}/${OQT_ROUTING_THRESHOLD:-0.02}/${OQT_ROUTING_MAX_LAYERS:-0.25}" \
    "$OQT_LONG_SHARE/$OQT_LONG_LEN/$( hash_of < "$RUN/bundle-long.jsonl" 2>/dev/null || echo none)" | hash_of)"
# Memory headroom for the build. A sweep that starves macOS of memory freezes the
# machine until the kernel watchdog reboots it (seen mid-sweep on the 128 GB Mac),
# so say what to free before hours of work start. Warnings only: the build may fit.
if ! is_done build "$D_BUILD"; then
    if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
        log "WARNING: Docker is running but the build does not need it; its VM holds memory the build could use (colima stop)"
    fi
    mem_mb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))
    wired_mb="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
    if [ "${wired_mb:-0}" -gt 0 ] && [ "$wired_mb" -gt $(( mem_mb - 12288 )) ]; then
        log "WARNING: iogpu.wired_limit_mb=$wired_mb lets the GPU take all but $(( (mem_mb - wired_mb) / 1024 )) GB of RAM; macOS can freeze under the build. Leave it 16 GB below RAM: sudo sysctl iogpu.wired_limit_mb=$(( mem_mb - 16384 ))"
    fi
fi
# OQT_KEEP_BUILD=1 adopts the existing quant when only the pipeline's own scripts
# changed since it was built: allowed when it was built from this exact bundle.
if [ "${OQT_KEEP_BUILD:-0}" = 1 ] && ! is_done build "$D_BUILD"; then
    built_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["corpus_bundle_sha256"])' "$OUT/build.json" 2>/dev/null || true)"
    if [ -f "$OUT/oqt_report.json" ] && [ -n "$built_sha" ] && [ "$built_sha" = "$(shasum -a 256 "$BUNDLE" | awk '{print $1}')" ]; then
        awk -F'\t' '$1 != "build"' "$STATE" > "$STATE.tmp" || true
        mv "$STATE.tmp" "$STATE"
        printf '%s\t%s\t%s\t%s\n' build "$D_BUILD" "$(ts)" 0 >> "$STATE"
        log "build: kept $OUT (OQT_KEEP_BUILD=1; it was built from this same bundle)"
    else
        die "OQT_KEEP_BUILD=1 but $OUT was not built from this bundle (or is incomplete): leave it out to rebuild"
    fi
fi
run_stage build "$D_BUILD" env CORPUS_FILE="$BUNDLE" OQT_OVERWRITE=1 OQ_SKIP_PPL=1 OQT_M3=0 \
    OQT_LONG_FILE="$RUN/bundle-long.jsonl" OQT_LONG_SHARE="$OQT_LONG_SHARE" OQT_LONG_LEN="$OQT_LONG_LEN" \
    "$CORPUS_REPO/scripts/omlx_oqt.sh" "$LEVEL" "$NAME"

# Scored on the model's own held-out conversations (one M3 slice per group) plus
# heldout-written-se.txt, independent written text that no prompt was derived from.
EVAL_FILES="heldout-written-se.txt $(ls "$RUN"/heldout/heldout-oqt-*.txt 2>/dev/null | tr '\n' ' ')"
D_SCORE="$(printf '%s|%s|%s|%s' "$D_BUILD" "$(cat "$CORPUS_REPO"/eval/heldout-*.txt "$RUN"/heldout/heldout-oqt-*.txt 2>/dev/null | hash_of)" \
    "${OQ_SKIP_PPL:-0}/${OQT_M3:-1}/${M3_SEQ:-2048}/${M3_MAX_WINDOWS:-64}" "$(hash_of < "$CORPUS_REPO/scripts/score_vs_bf16.py")" | hash_of)"
if [ "${OQ_SKIP_PPL:-0}" = "1" ] && [ "${OQT_M3:-1}" = "0" ]; then
    log "score: skipped (OQ_SKIP_PPL=1 and OQT_M3=0)"
else
    run_stage score "$D_SCORE" env OQT_SCORE_ONLY=1 M3_FILES="${M3_FILES:-$EVAL_FILES}" \
        PPL_FILES="${PPL_FILES:-$EVAL_FILES}" "$CORPUS_REPO/scripts/omlx_oqt.sh" "$LEVEL" "$NAME"
fi


# ------------------------------------------------------------- agent eval
# The quant works the same agent tasks, same samples and efforts, as the generator
# did for the calibration; solved checks are compared task by task. Sessions are
# cached per build (a rebuilt quant is evaluated afresh).
if [ "${OQT_AGENT_EVAL:-0}" = 1 ]; then
    [ "$OQT_AGENT" = 1 ] || die "OQT_AGENT_EVAL=1 compares with the generator's agent sessions, so it needs OQT_AGENT=1"
    D_AGENT_EVAL="$(printf '%s|%s' "$D_BUILD" "$D_AGENT" | hash_of)"
    EVAL_DIR="$RUN/agent-eval/$D_BUILD"
    if ! is_done agent-eval "$D_AGENT_EVAL"; then
        if [ "$AGENT_SANDBOX" = docker ]; then
            docker info >/dev/null 2>&1 || die "the agent eval needs Docker: start colima or OrbStack, then rerun the same command"
            docker_check
        fi
        start_server "$OUT"
    fi
    run_stage agent-eval "$D_AGENT_EVAL" agent_sessions "$EVAL_DIR" "$EVAL_DIR" "$QUANT_ID"
    stop_server
    python3 "$CORPUS_REPO/scripts/results.py" agent-eval --generator "$PREP_OUT/answers/$GEN_ID" \
        --quant "$EVAL_DIR/answers/$QUANT_ID" --render "$PREP_OUT/answers/$GEN_ID/render-$OQT_PROFILE.json" \
        --json "$RUN/agent-eval.json" | while IFS= read -r l; do log "agent eval: $l"; done \
        || log "WARNING: could not compare the agent sessions (see $EVAL_DIR)"
fi

# ----------------------------------------------------------------- summary
python3 "$CORPUS_REPO/scripts/results.py" collect --run "$RUN" --quant "$OUT" --level "$LEVEL" \
    --model "$MODEL_ID" --variant "$OQT_VARIANT" --oqup "$OQUP" >/dev/null \
    || log "WARNING: could not write $RUN/result.json"
log "=== done ==="
log "quant     : $OUT"
if [ -n "$OUT" ] && [ -f "$OUT/oqt_report.json" ]; then
    log "oQ-T      : $(summary oqt "$OUT/oqt_report.json")"
fi
[ -f "$PREP_OUT/answers/$GEN_ID/render-$OQT_PROFILE.json" ] && \
    log "calibration: $(summary render "$PREP_OUT/answers/$GEN_ID/render-$OQT_PROFILE.json")"
python3 "$CORPUS_REPO/scripts/results.py" vs-previous --oqup "$OQUP" --run "$RUN" 2>/dev/null \
    | while IFS= read -r l; do log "$l"; done || true
log "all runs  : $0 results"
log "serve it  : ln -s \"$OUT\" ~/.omlx/models/"
