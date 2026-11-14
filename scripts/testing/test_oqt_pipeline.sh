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
trap 'pkill -f "stub_omlx.py .* $T/" 2>/dev/null || true; [ "${KEEP:-0}" = 1 ] || rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; echo "kept for inspection: $T" >&2; KEEP=1; exit 1; }
pass() { echo "ok   $*"; }
count() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],0))" "$T/counter.json" "$1"; }

SRC="$T/hub/models--Qwen--Qwen3.8-Flash-Next/snapshots/abc"
( cd "$OMLX_REPO" && "$VPY" "$HERE/make_tiny_source.py" "$SRC" ) >/dev/null
GEN="$T/models-out/Qwen3.8-Flash-Next-oQ5e-gen"; mkdir -p "$GEN"
echo '{"model_type":"qwen4_exp","quantization":{"bits":5}}' > "$GEN/config.json"
export OQUP="$T/oqup" MODELS_OUT="$T/models-out" HF_HUB_CACHE="$T/hub" GENERATOR="$GEN"
export PORT="${TEST_PORT:-8799}" SERVER_WAIT=30 OQ_SAMPLES=32 OQ_SEQLEN=8 OQ_SKIP_PPL=1 CONCURRENCY=4
# Agent sessions: a tiny task the scripted stand-in agent can solve, local sandbox.
mkdir -p "$T/agent-tasks/answer-42/repo"
echo "Write the answer to answer.txt." > "$T/agent-tasks/answer-42/repo/README.md"
printf '%s' '{"id": "answer-42", "domain": "test", "image": "unused", "prompt": "Write 42 into answer.txt and verify it.", "check": "grep -qx 42 answer.txt"}' > "$T/agent-tasks/answer-42/task.json"
export OQT_AGENT_TASKS="$T/agent-tasks" OQT_AGENT_SANDBOX=local AGENT_SAMPLES=2
# Long windows scaled to the tiny model: 64-token windows over 32 x 8-token short ones.
export OQT_LONG_LEN=64 OQT_LONG_SHARE=0.25
# M3 scoring scaled to the tiny model.
export M3_SEQ=16 M3_MAX_WINDOWS=4
export OQT_SERVE_CMD="python3 -I $HERE/stub_omlx.py \$PORT $T/counter.json"
P="$REPO/scripts/oqt_pipeline.sh"
reset() { echo '{}' > "$T/counter.json"; }

reset; BUDGET_TOKENS=3000 "$P" 4 t >/dev/null 2>&1 || fail "fresh run failed (see $T/oqup/runs/t)"
first="$(count generate)"
OUT="$T/models-out/Qwen3.8-Flash-Next-oQ4t-t"
[ -f "$OUT/oqt_report.json" ] && [ -f "$OUT/build.json" ] || fail "no quant/report written"
grep -q '<|im_start|>' "$T/oqup/runs/t/bundle.txt" || fail "bundle is not in the chat template"
grep -q '<think>' "$T/oqup/runs/t/bundle.txt" || fail "bundle has no thinking"
pass "fresh run: prompts -> answers -> chat-template bundle -> oQ-T quant"
python3 - "$OUT/oqt_report.json" "$T/oqup/runs/t/bundle-long.jsonl" "$T/oqup/runs/t/prep/answers/Qwen3.8-Flash-Next-oQ5e-gen/agent.json" <<'PYCHECK' || fail "agent sessions or long windows missing"
import json, sys
cal = json.load(open(sys.argv[1]))["summary"]["calibration_windows"]
assert cal["long_windows"] >= 1 and cal["long_len"] == 64, cal
long_docs = [json.loads(l) for l in open(sys.argv[2])]
assert long_docs and all(d["text"] for d in long_docs)
agent = json.load(open(sys.argv[3]))
assert agent["kept"] == 2 and agent["solved"] == 2, agent
PYCHECK
grep -q "answer.txt" "$T/oqup/runs/t/bundle.txt" || fail "agent sessions not in the calibration bundle"
pass "agent sessions solved and rendered; long documents packed into long windows"
M3J="$(ls "$T"/oqup/m3-*-oQ4-t-oqt.json 2>/dev/null | head -1 || true)"
[ -n "$M3J" ] || fail "no M3 score file"
python3 - "$M3J" <<'PYCHECK' || fail "M3 score incomplete"
import json, sys
r = json.load(open(sys.argv[1]))
o = r["overall"]
assert o["kl"] >= 0 and 0 <= o["top1"] <= 1 and o["tokens"] > 0, o
assert r["routing_by_layer"], "no routing stats"
assert "heldout-written-se" in r["slices"] and any(k.startswith("heldout-oqt-") for k in r["slices"]), r["slices"].keys()
PYCHECK
python3 - "$T/oqup/runs/t/prep/answers/Qwen3.8-Flash-Next-oQ5e-gen/render-profile.json" "$T/oqup/runs/t/bundle.txt" "$T/oqup/runs/t/bundle-long.jsonl" <<'PYCHECK' || fail "held-out conversations leak into the calibration"
import json, sys
held = json.load(open(sys.argv[1]))["heldout"]
assert held and set(held) <= {"corpus", "generic", "broad", "agent"}, held   # tiny budget: only groups with 5+ prompts hold out
calib = open(sys.argv[2]).read() + open(sys.argv[3]).read()
for g, h in held.items():
    text = open(h["file"]).read()
    # every held-out conversation's own text (the part after its user turn) is absent from the calibration
    for doc in text.split("<|im_start|>user")[1:]:
        assert doc[:200] not in calib, (g, doc[:80])
PYCHECK
ls "$T"/oqup/anchors/m3-*.npz >/dev/null 2>&1 || fail "M3 reference not cached"
pass "M3: quant scored against the streamed original on held-out own conversations + heldout-written-se (none calibrated on)"

reset; BUDGET_TOKENS=3000 "$P" 4 t >/dev/null 2>&1 || fail "identical rerun failed"
[ "$(count generate)" = 0 ] && [ "$(count derive)" = 0 ] || fail "identical rerun sent requests"
[ "$(grep -c 'up to date, skipped' "$T/oqup/runs/t/pipeline.log")" -ge 5 ] || fail "stages not skipped"
pass "identical rerun: nothing redone, no requests"

reset; OQT_CHANGE_SETTINGS=1 BUDGET_TOKENS=6000 "$P" 4 t >/dev/null 2>&1 || fail "budget change run failed"
[ "$(count derive)" = 0 ] || fail "budget change re-derived"
# Doubling the budget asks only for the new answers: fewer than a run from scratch,
# which would need about twice the first run's requests.
n="$(count generate)"; [ "$n" -gt 0 ] && [ "$n" -lt "$first" ] || fail "budget change sent $n generate requests (first run: $first; expected only the new ones)"
pass "budget change: only generate/render/build rerun, only new answers requested ($n)"

reset; OQT_CHANGE_SETTINGS=1 STUB_DELAY=1.0 BUDGET_TOKENS=60000 "$P" 4 t >"$T/kill.out" 2>&1 & pid=$!
sleep 8; kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
[ "$rc" = 130 ] || fail "kill: exit code $rc, expected 130"
before="$(count generate)"; sleep 2
[ "$(count generate)" = "$before" ] || fail "requests continued after the kill"
pgrep -f "stub_omlx.py .*$T/" >/dev/null && fail "server left running after the kill"
reset; BUDGET_TOKENS=60000 "$P" 4 t >/dev/null 2>&1 || fail "resume run failed"
total="$(python3 -c "import json,glob,sys;print(json.load(open(glob.glob(sys.argv[1])[0]))['requests'])" "$T/oqup/runs/t/prep/answers/*/generate-profile.json")"
[ "$(count generate)" -lt "$total" ] || fail "resume re-requested cached answers"
pass "kill mid-generate: stopped at once, server stopped; resume reused $((total - $(count generate)))/$total answers"

reset; "$P" 4 t >"$T/plain.out" 2>&1 || fail "resume without settings failed"
[ "$(count generate)" = 0 ] || fail "resume without settings did not reuse the saved budget"
grep -qx "BUDGET_TOKENS=60000" "$T/oqup/runs/t/settings.env" || fail "budget not saved in settings.env"
reset; BUDGET_TOKENS=1234 "$P" 4 t >"$T/mismatch.out" 2>&1 && fail "a different setting did not stop the run"
grep -q "BUDGET_TOKENS: saved '60000', given '1234'" "$T/mismatch.out" || fail "no clear message for a changed setting"
[ "$(count generate)" = 0 ] || fail "a refused run sent requests"
pass "settings kept per run: a bare resume reuses them, a different value is refused"

reset; OQT_SERVE_CMD="exit 3" BUDGET_TOKENS=3000 "$P" 4 broken >"$T/broken.out" 2>&1 && fail "broken server did not fail"
grep -q "the oMLX server exited" "$T/broken.out" || fail "no clear message for a dead server"
pass "dead server: clear error"

st="$("$P" status t)"; grep -q "build      done" <<< "$st" || fail "status does not show the finished build"
pass "status command"

# A build recorded under another digest (as after an edit of the pipeline's scripts):
# OQT_KEEP_BUILD=1 adopts it when it was built from the same bundle, and refuses otherwise.
ST="$T/oqup/runs/t/state.tsv"
awk -F'\t' '$1 != "build" && $1 != "score"' "$ST" > "$ST.tmp" && mv "$ST.tmp" "$ST"
printf 'build\tolddigest\t-\t0\n' >> "$ST"
reset; OQT_KEEP_BUILD=1 "$P" 4 t >/dev/null 2>&1 || fail "OQT_KEEP_BUILD run failed"
grep -q "build: kept" "$T/oqup/runs/t/pipeline.log" || fail "OQT_KEEP_BUILD did not keep the build"
grep -q "^build	[0-9a-f]" "$ST" && ! grep -q "olddigest" "$ST" || fail "kept build not recorded under the new digest"
awk -F'\t' '$1 != "build" && $1 != "score"' "$ST" > "$ST.tmp" && mv "$ST.tmp" "$ST"
BJ="$T/models-out/Qwen3.8-Flash-Next-oQ4t-t/build.json"; cp "$BJ" "$T/build.json.bak"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["corpus_bundle_sha256"]="0"*64; json.dump(d,open(sys.argv[1],"w"))' "$BJ"
reset; OQT_KEEP_BUILD=1 "$P" 4 t >"$T/keep.out" 2>&1 && fail "OQT_KEEP_BUILD adopted a build of another bundle"
grep -q "was not built from this bundle" "$T/keep.out" || fail "no clear message when the build cannot be kept"
cp "$T/build.json.bak" "$BJ"; reset; OQT_KEEP_BUILD=1 "$P" 4 t >/dev/null 2>&1 || fail "OQT_KEEP_BUILD rerun failed"
pass "OQT_KEEP_BUILD: adopts a build of the same bundle after a script change, refuses another bundle"

reset; OQT_AGENT_EVAL=1 "$P" 4 t >"$T/eval.out" 2>&1 || fail "agent eval run failed (see $T/oqup/runs/t/pipeline.log)"
[ "$(count derive)" = 0 ] && [ "$(count agent)" -gt 0 ] || fail "agent eval reran other stages or ran no sessions"
grep -q "agent eval: quant solved" "$T/oqup/runs/t/pipeline.log" || fail "no agent eval comparison in the log"
python3 - "$T/oqup/runs/t/result.json" <<'PYCHECK' || fail "result.json incomplete"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["model"] == "qwen3.8-flash-next" and r["level"] == 4 and r["variant"] == "", r
assert r["m3"]["written_kl"] >= 0 and "own_kl" in r["m3"], r["m3"]
ae = r["agent_eval"]
assert ae["quant"]["sessions"] == 2 and ae["generator"]["sessions"] == 2, ae
PYCHECK
"$P" results | grep -q "Qwen3.8-Flash-Next-oQ4t-t" || fail "results table does not list the run"
reset; OQT_AGENT_EVAL=1 "$P" 4 t >/dev/null 2>&1 || fail "agent eval rerun failed"
[ "$(count agent)" = 0 ] || fail "agent eval rerun sent requests"
pass "agent eval: the quant works the agent tasks, compared with the generator; results table; rerun cached"

# oQ-T+ from the same answers: a new run name, nothing regenerated, no layer cap,
# and a comparison with a verdict.
reset; OQT_PLUS=1 BUDGET_TOKENS=60000 "$P" 4 tp >/dev/null 2>&1 || fail "oQ-T+ run failed (see $T/oqup/runs/tp)"
# (CONCURRENCY=4 here: requests in flight at the budget's edge may be new; under 5% of ~240)
[ "$(count generate)" -le 12 ] && [ "$(count agent)" = 0 ] && [ "$(count derive)" = 0 ] || fail "oQ-T+ run regenerated answers: $(cat "$T/counter.json")"
grep -qx "OQT_ROUTING_MAX_LAYERS=1.0" "$T/oqup/runs/tp/settings.env" && grep -qx "OQT_ROUTING_THRESHOLD=0.01" "$T/oqup/runs/tp/settings.env" \
    || fail "oQ-T+ preset not applied"
python3 - "$T/oqup/runs/tp/result.json" <<'PYCHECK' || fail "oQ-T+ result incomplete"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["plus"] is True and r["routing"]["layers"] > 0 and r["routing"]["missed"] == 0, r.get("routing")
PYCHECK
"$P" compare t tp >"$T/compare.out" 2>&1 || fail "compare failed: $(cat "$T/compare.out")"
grep -q "tp (oQ-T+) compared with t" "$T/compare.out" && grep -q "^Verdict: " "$T/compare.out" \
    && grep -q "KL, held-out conversations" "$T/compare.out" || fail "compare output unclear: $(cat "$T/compare.out")"
"$P" results | grep -q "(oQ-T+)" || fail "results table does not mark the oQ-T+ run"
pass "oQ-T+: built from the same answers (nothing regenerated), every drifting layer protected; compare gives a verdict"

# Generation speed: the bench compares MTP settings and puts the model's own back;
# OQT_MTP sets it for a run.
reset; OQT_MTP=3 STUB_DECODE_DELAY=0.2 "$P" bench >"$T/bench.out" 2>&1 || fail "bench failed: $(tail -5 "$T/bench.out")"
grep -q "decoding  : MTP 3" "$T/oqup/runs/bench/pipeline.log" || fail "OQT_MTP not applied at server start"
grep -q "its setting now: MTP 3" "$T/bench.out" && grep -q "restored the model's own setting: MTP 3" "$T/bench.out" \
    || fail "bench did not restore the setting: $(cat "$T/bench.out")"
grep -q "<- fastest" "$T/bench.out" || fail "bench printed no result"
pass "bench: MTP settings timed side by side, the model's setting restored; OQT_MTP applied at server start"

# The template check: a profile that does not fit the source's template stops the run in preflight.
python3 - "$REPO/models/qwen3.8-flash-next.json" "$T/string-args.json" <<'PYCHECK'
import json, sys
p = json.load(open(sys.argv[1])); p["render"]["tool_arguments"] = "string"
json.dump(p, open(sys.argv[2], "w"))
PYCHECK
reset; OQT_MODEL="$T/string-args.json" BUDGET_TOKENS=3000 "$P" 4 badtpl >"$T/badtpl.out" 2>&1 && fail "a template mismatch did not stop the run"
grep -q "does not fit profile" "$T/badtpl.out" || fail "no clear message for a template mismatch"
[ "$(count generate)" = 0 ] && [ "$(count derive)" = 0 ] || fail "a template mismatch sent requests"
pass "template check: a profile that does not fit the chat template fails in preflight"

# A variant: a local fine-tune named <name>-uncensored and its own quant write the
# answers; the official generator is never picked for it.
cp -R "$SRC" "$T/models-out/Qwen3.8-Flash-Next-uncensored"
UG="$T/models-out/Qwen3.8-Flash-Next-uncensored-oQ5e-gen"; mkdir -p "$UG"
echo '{"model_type":"qwen4_exp","quantization":{"bits":5}}' > "$UG/config.json"
reset; env -u GENERATOR OQT_VARIANT=uncensored BUDGET_TOKENS=3000 "$P" 4 u >/dev/null 2>&1 || fail "variant run failed (see $T/oqup/runs/u)"
grep -qx "GENERATOR=.*/models-out/Qwen3.8-Flash-Next-uncensored-oQ5e-gen" "$T/oqup/runs/u/settings.env" || fail "variant run did not pick the variant's quant: $(grep GENERATOR= "$T/oqup/runs/u/settings.env")"
grep -qx "SRC=.*/models-out/Qwen3.8-Flash-Next-uncensored" "$T/oqup/runs/u/settings.env" || fail "variant run did not use the variant's source"
grep -qx "OQT_VARIANT=uncensored" "$T/oqup/runs/u/settings.env" || fail "variant not saved with the run"
[ -f "$T/models-out/Qwen3.8-Flash-Next-uncensored-oQ4t-u/oqt_report.json" ] || fail "variant quant not named after the variant"
reset; env -u GENERATOR "$P" 4 u >/dev/null 2>&1 && [ "$(count generate)" = 0 ] || fail "variant resume did not reuse its settings"
pass "variant: own source, own generator, own output name; resumes with its settings"

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
