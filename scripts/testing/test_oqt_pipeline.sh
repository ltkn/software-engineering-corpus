#!/usr/bin/env bash
# test_oqt_pipeline.sh — end-to-end check of scripts/oqt_pipeline.sh on a tiny
# model, with a stand-in oMLX server for derive/generate and a REAL oQ-T build.
# Runs on any Mac with the oMLX feat/oqt checkout; takes about a minute.
#
#   OMLX_REPO=~/dev/omlx scripts/testing/test_oqt_pipeline.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export OMLX_REPO="${OMLX_REPO:-$HOME/dev/omlx}"
VPY="$OMLX_REPO/.venv-3.12/bin/python"
T="$(mktemp -d "${TMPDIR:-/tmp}/oqt-pipeline-test.XXXXXX")"
trap 'pkill -f "stub_omlx.py .* $T/" 2>/dev/null || true; rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok   $*"; }
count() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],0))" "$T/counter.json" "$1"; }

SRC="$T/hub/models--Qwen--Qwen3.8-Flash-Next/snapshots/abc"
( cd "$OMLX_REPO" && "$VPY" "$HERE/make_tiny_source.py" "$SRC" ) >/dev/null
GEN="$T/models-out/Qwen3.8-Flash-Next-oQ5e-gen"; mkdir -p "$GEN"
echo '{"model_type":"qwen4_exp","quantization":{"bits":5}}' > "$GEN/config.json"
export OQUP="$T/oqup" MODELS_OUT="$T/models-out" HF_HUB_CACHE="$T/hub" GENERATOR="$GEN"
export PORT="${TEST_PORT:-8799}" SERVER_WAIT=30 OQ_SAMPLES=4 OQ_SEQLEN=8 OQ_SKIP_PPL=1 CONCURRENCY=4
export OQT_SERVE_CMD="python3 -I $HERE/stub_omlx.py \$PORT $T/counter.json"
P="$REPO/scripts/oqt_pipeline.sh"
reset() { echo '{}' > "$T/counter.json"; }

reset; BUDGET_TOKENS=3000 "$P" 4 t >/dev/null 2>&1 || fail "fresh run failed (see $T/oqup/runs/t)"
OUT="$T/models-out/Qwen3.8-Flash-Next-oQ4t-t"
[ -f "$OUT/oqt_report.json" ] && [ -f "$OUT/build.json" ] || fail "no quant/report written"
grep -q '<|im_start|>' "$T/oqup/runs/t/bundle.txt" || fail "bundle is not in the chat template"
grep -q '<think>' "$T/oqup/runs/t/bundle.txt" || fail "bundle has no thinking"
pass "fresh run: prompts -> answers -> chat-template bundle -> oQ-T quant"

reset; BUDGET_TOKENS=3000 "$P" 4 t >/dev/null 2>&1 || fail "identical rerun failed"
[ "$(count generate)" = 0 ] && [ "$(count derive)" = 0 ] || fail "identical rerun sent requests"
[ "$(grep -c 'up to date, skipped' "$T/oqup/runs/t/pipeline.log")" -ge 5 ] || fail "stages not skipped"
pass "identical rerun: nothing redone, no requests"

reset; BUDGET_TOKENS=6000 "$P" 4 t >/dev/null 2>&1 || fail "budget change run failed"
[ "$(count derive)" = 0 ] || fail "budget change re-derived"
n="$(count generate)"; [ "$n" -gt 0 ] && [ "$n" -lt 20 ] || fail "budget change sent $n generate requests (expected only the new ones)"
pass "budget change: only generate/render/build rerun, only new answers requested ($n)"

reset; STUB_DELAY=1.0 BUDGET_TOKENS=60000 "$P" 4 t >"$T/kill.out" 2>&1 & pid=$!
sleep 8; kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
[ "$rc" = 130 ] || fail "kill: exit code $rc, expected 130"
before="$(count generate)"; sleep 2
[ "$(count generate)" = "$before" ] || fail "requests continued after the kill"
pgrep -f "stub_omlx.py .*$T/" >/dev/null && fail "server left running after the kill"
reset; BUDGET_TOKENS=60000 "$P" 4 t >/dev/null 2>&1 || fail "resume run failed"
total="$(python3 -c "import json,glob,sys;print(json.load(open(glob.glob(sys.argv[1])[0]))['requests'])" "$T/oqup/runs/t/prep/answers/*/generate-profile.json")"
[ "$(count generate)" -lt "$total" ] || fail "resume re-requested cached answers"
pass "kill mid-generate: stopped at once, server stopped; resume reused $((total - $(count generate)))/$total answers"

reset; OQT_SERVE_CMD="exit 3" BUDGET_TOKENS=3000 "$P" 4 broken >"$T/broken.out" 2>&1 && fail "broken server did not fail"
grep -q "the oMLX server exited" "$T/broken.out" || fail "no clear message for a dead server"
pass "dead server: clear error"

st="$("$P" status t)"; grep -q "build      done" <<< "$st" || fail "status does not show the finished build"
pass "status command"

GJ="$T/oqup/runs/t/prep/answers/Qwen3.8-Flash-Next-oQ5e-gen/generate-profile.json"
python3 - "$GJ" "$T/oqup/runs/t/prep/seed_prompts.jsonl" <<'PYCHECK' || fail "profile mix or tool calls missing"
import json, sys
g = json.load(open(sys.argv[1]))
seeds = [json.loads(l) for l in open(sys.argv[2])]
assert set(g["tokens_by_group"]) == {"corpus", "generic", "broad"}, g["tokens_by_group"]
assert all(v > 0 for v in g["tokens_by_group"].values()), g["tokens_by_group"]
assert any(s.get("tools") for s in seeds), "no tool-carrying seed prompts"
assert g["with_tool_calls"] > 0, "no answers with tool calls"
PYCHECK
pass "profile mix: corpus + generic + broad, tool calls kept"

reset; OQT_PROFILE=generic BUDGET_TOKENS=6000 "$P" 4 g >/dev/null 2>&1 || fail "generic profile run failed"
[ "$(count seed)" = 0 ] && [ "$(count derive)" = 0 ] || fail "generic run re-requested cached seeds or derives"
GG="$T/oqup/runs/g/prep/answers/Qwen3.8-Flash-Next-oQ5e-gen/generate-generic.json"
python3 - "$GG" <<'PYCHECK' || fail "generic profile used corpus prompts"
import json, sys
g = json.load(open(sys.argv[1]))
assert set(g["tokens_by_group"]) == {"generic", "broad"}, g["tokens_by_group"]
PYCHECK
[ -f "$T/models-out/Qwen3.8-Flash-Next-oQ4t-g/oqt_report.json" ] || fail "generic arm quant not built"
pass "generic arm: no corpus prompts, shared cache reused ($(count generate) new answers)"
reset; OQT_MIX=corpus=100 BUDGET_TOKENS=3000 "$P" 4 c >/dev/null 2>&1 || fail "corpus-only run failed"
grep -q "seed: skipped" "$T/oqup/runs/c/pipeline.log" || fail "corpus-only run did not skip the seed stage"
[ "$(count seed)" = 0 ] || fail "corpus-only run sent seed requests"
python3 - "$T/oqup/runs/c/prep/answers/Qwen3.8-Flash-Next-oQ5e-gen/generate-profile.json" <<'PYCHECK' || fail "corpus-only run used seed prompts"
import json, sys
assert set(json.load(open(sys.argv[1]))["tokens_by_group"]) == {"corpus"}
PYCHECK
pass "corpus-only mix: seed stage skipped, corpus prompts only"

echo "all pipeline checks passed"
