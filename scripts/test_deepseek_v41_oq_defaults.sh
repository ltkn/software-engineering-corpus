#!/usr/bin/env bash
# test_deepseek_v41_oq_defaults.sh — what the DeepSeek V4.1 builders emit.
#
# Runs the builders with --dry-run against a fake original checkpoint, so this
# needs no model download, no MLX install and no quant host: source discovery
# stops at config.json plus model.safetensors.index.json, and --dry-run writes
# the runner(s) and exits before the quantizer is launched. Assertions are on
# the emitted quantize_oq_streaming(...) calls and on the stock-reuse decision,
# which are the only things the builders contribute to the output's layout.
#
# Usage: bash scripts/test_deepseek_v41_oq_defaults.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FAILURES=0
DRY_EXIT=0
# The stock-reuse check runs inside $VENV_PY and needs only json from stdlib.
CHECK_PY="$(command -v python3 || true)"

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
skip() { printf 'skip %s\n' "$1"; }

assert_contains() { # <label> <file> <needle>
    if [ ! -f "$2" ]; then
        fail "$1 — $(basename "$2") was not written"
    elif grep -qF -- "$3" "$2"; then pass "$1"; else
        fail "$1 — missing '$3' in $(basename "$2")"
        sed -n '1,20p' "$2" | sed 's/^/       | /'
    fi
}

assert_absent() { # <label> <file> <needle>
    if [ ! -f "$2" ]; then
        fail "$1 — $(basename "$2") was not written"
    elif grep -qF -- "$3" "$2"; then
        fail "$1 — unexpected '$3' in $(basename "$2")"
        grep -nF -- "$3" "$2" | sed 's/^/       | /'
    else
        pass "$1"
    fi
}

assert_exit() { # <label> <expected code> <actual code>
    if [ "$2" = "$3" ]; then pass "$1"; else
        fail "$1 — exit $3, expected $2"
    fi
}

assert_same() { # <label> <file a> <file b>
    if cmp -s "$2" "$3"; then pass "$1"; else
        fail "$1 — $(basename "$2") and $(basename "$3") differ"
        diff "$2" "$3" | sed 's/^/       | /'
    fi
}

assert_says() { # <label> <output file> <needle>
    if grep -qF -- "$3" "$2"; then pass "$1"; else
        fail "$1 — output has no '$3'"
        tail -8 "$2" | sed 's/^/       | /'
    fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dsv41-defaults.XXXXXX")"
LIVE_PID=""
cleanup() {
    if [ -n "$LIVE_PID" ]; then
        kill "$LIVE_PID" 2>/dev/null
        wait "$LIVE_PID" 2>/dev/null
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

SRC="$WORK/src"
mkdir -p "$SRC" "$WORK/oqup" "$WORK/models-out" "$WORK/hf" "$WORK/omlx"
# An "original" checkpoint as far as the builders check: model_type deepseek_v41
# and no omlx_deepseek_v41 section. Weights are never opened on this path.
printf '{"model_type":"deepseek_v41","dtype":"bfloat16"}\n' > "$SRC/config.json"
printf '{}\n' > "$SRC/model.safetensors.index.json"
# A non-empty bundle keeps the shared /tmp corpus rebuild out of the test.
printf 'calibration stub\n' > "$WORK/corpus.txt"

export VENV_PY=/usr/bin/true
export OQUP="$WORK/oqup"
export MODELS_OUT="$WORK/models-out"
export HF_HUB_CACHE="$WORK/hf"
export OMLX_REPO="$WORK/omlx"
export CORPUS_FILE="$WORK/corpus.txt"
export OQ_SKIP_STOCK=1

dry_run() { # <script> <version> [extra args after the flags]
    local script="$1" version="$2"
    shift 2
    ( cd "$REPO" && bash "scripts/$script" "$version" --src "$SRC" --dry-run "$@" ) \
        > "$WORK/$version.out" 2>&1
    DRY_EXIT=$?
}

dry_run_width() { # <script> <version> <ngram_bits>
    # The width is a positional argument, so it goes before the flags.
    local script="$1" version="$2" width="$3"
    ( cd "$REPO" && bash "scripts/$script" "$version" "$width" --src "$SRC" --dry-run ) \
        > "$WORK/$version.out" 2>&1
    DRY_EXIT=$?
}

dry_run_env() { # <script> <version> <KEY=VAL...>
    local script="$1" version="$2"
    shift 2
    ( cd "$REPO" && env "$@" bash "scripts/$script" "$version" --src "$SRC" --dry-run ) \
        > "$WORK/$version.out" 2>&1
    DRY_EXIT=$?
}

dry_run_width_env() { # <script> <version> <ngram_bits> <KEY=VAL...>
    local script="$1" version="$2" width="$3"
    shift 3
    ( cd "$REPO" && env "$@" bash "scripts/$script" "$version" "$width" --src "$SRC" --dry-run ) \
        > "$WORK/$version.out" 2>&1
    DRY_EXIT=$?
}

printf '== syntax ==\n'
for script in "$REPO"/scripts/omlx_*.sh; do
    if bash -n "$script" 2>"$WORK/syn.err"; then
        pass "bash -n $(basename "$script")"
    else
        fail "bash -n $(basename "$script")"
        cat "$WORK/syn.err" | sed 's/^/       | /'
    fi
done

printf '== the default keeps the stock FP8 tables ==\n'
for pair in "omlx_deepseek_v41_oq4e.sh t2-oq4 oq4e" \
            "omlx_deepseek_v41_oq3e.sh t2-oq3 oq3e" \
            "omlx_deepseek_v41_oq25e.sh t2-oq25 oq2.5e"; do
    set -- $pair
    dry_run "$1" "$2"
    RUNNER="$OQUP/run_$3_$2.py"
    assert_contains "$1 copies the source tables" "$RUNNER" "preserve_ngram_table=True,"
    assert_absent "$1 asks for no affine width" "$RUNNER" "ngram_bits="
    assert_absent "$1 passes no allocation flag" "$RUNNER" "legacy_allocation"
done
dry_run omlx_deepseek_v41_oq4e.sh t2-oq4
RUNNER="$OQUP/run_oq4e_t2-oq4.py"
assert_contains "custom corpus still drives imatrix" "$RUNNER" "calib_dataset="
assert_contains "custom corpus still drives sensitivity" "$RUNNER" "sensitivity_calib_dataset="

printf '== an explicit width still selects affine ==\n'
cp "$RUNNER" "$WORK/default.runner"
dry_run_env omlx_deepseek_v41_oq4e.sh t2-env4 NGRAM_BITS=4
assert_exit "NGRAM_BITS=4 runs" 0 "$DRY_EXIT"
assert_contains "NGRAM_BITS=4 emits the width" "$OQUP/run_oq4e_t2-env4.py" "ngram_bits=4,"
assert_absent "NGRAM_BITS=4 drops the copy" "$OQUP/run_oq4e_t2-env4.py" "preserve_ngram_table="
dry_run_width omlx_deepseek_v41_oq4e.sh t2-pos4 4
assert_exit "the positional 4 runs" 0 "$DRY_EXIT"
assert_contains "the positional 4 emits the width" "$OQUP/run_oq4e_t2-pos4.py" "ngram_bits=4,"
assert_absent "the positional 4 drops the copy" "$OQUP/run_oq4e_t2-pos4.py" "preserve_ngram_table="
dry_run_env omlx_deepseek_v41_oq4e.sh t2-off PRESERVE_NGRAM_TABLE=0
assert_exit "PRESERVE_NGRAM_TABLE=0 runs" 0 "$DRY_EXIT"
assert_contains "PRESERVE_NGRAM_TABLE=0 keeps 8-bit affine" "$OQUP/run_oq4e_t2-off.py" "ngram_bits=8,"
assert_absent "PRESERVE_NGRAM_TABLE=0 asks no copy" "$OQUP/run_oq4e_t2-off.py" "preserve_ngram_table="

printf '== a width and a copy are not both honoured ==\n'
dry_run_width_env omlx_deepseek_v41_oq4e.sh t2-conflict-pos 8 PRESERVE_NGRAM_TABLE=1
assert_exit "preserve with the positional 8 exits 2" 2 "$DRY_EXIT"
assert_says "the positional conflict names the positional" "$WORK/t2-conflict-pos.out" \
    "PRESERVE_NGRAM_TABLE=1 conflicts with the ngram_bits positional"
dry_run_env omlx_deepseek_v41_oq4e.sh t2-conflict-env PRESERVE_NGRAM_TABLE=1 NGRAM_BITS=4
assert_exit "preserve with NGRAM_BITS=4 exits 2" 2 "$DRY_EXIT"
assert_says "the env conflict names NGRAM_BITS" "$WORK/t2-conflict-env.out" "NGRAM_BITS=4"
dry_run_env omlx_deepseek_v41_oq4e.sh t2-bad-width NGRAM_BITS=5
assert_exit "NGRAM_BITS=5 exits 2" 2 "$DRY_EXIT"
assert_says "the width error lists the supported widths" "$WORK/t2-bad-width.out" "2 3 4 6 8"
dry_run_env omlx_deepseek_v41_oq4e.sh t2-bad-preserve PRESERVE_NGRAM_TABLE=2
assert_exit "PRESERVE_NGRAM_TABLE=2 exits 2" 2 "$DRY_EXIT"

printf '== OQ_LEGACY_ALLOCATION is not read ==\n'
dry_run_env omlx_deepseek_v41_oq4e.sh t2-oq4 OQ_LEGACY_ALLOCATION=0
assert_exit "OQ_LEGACY_ALLOCATION=0 runs" 0 "$DRY_EXIT"
assert_same "OQ_LEGACY_ALLOCATION=0 changes nothing" "$WORK/default.runner" "$RUNNER"
dry_run_env omlx_deepseek_v41_oq4e.sh t2-oq4 OQ_LEGACY_ALLOCATION=bogus
assert_exit "an invalid value is not rejected" 0 "$DRY_EXIT"
assert_same "an invalid value changes nothing" "$WORK/default.runner" "$RUNNER"

printf '== both arms carry the same Engram setting ==\n'
dry_run_env omlx_deepseek_v41_oq4e.sh t2-stock OQ_SKIP_STOCK=0
assert_exit "a dry run with stock enabled succeeds" 0 "$DRY_EXIT"
STOCK_RUNNER="$OQUP/run_oq4e_src_stock.py"
if [ -f "$STOCK_RUNNER" ]; then
    pass "the dry run emits the stock runner"
    custom_line="$(grep -E 'preserve_ngram_table|ngram_bits' "$RUNNER" | tr -d ' ')"
    stock_line="$(grep -E 'preserve_ngram_table|ngram_bits' "$STOCK_RUNNER" | tr -d ' ')"
    if [ -n "$custom_line" ] && [ "$custom_line" = "$stock_line" ]; then
        pass "stock and custom request the same Engram setting ($custom_line)"
    else
        fail "stock and custom request the same Engram setting (custom='$custom_line' stock='$stock_line')"
    fi
    assert_says "the stock arm records the live label, not a literal" \
        "$REPO/scripts/omlx_deepseek_v41_oq4e.sh" \
        'write_build_json "$STOCK_OUT" "stock-default" "$NGRAM_LABEL"'
else
    fail "the dry run emits the stock runner"
    tail -8 "$WORK/t2-stock.out" | sed 's/^/       | /'
    skip "the stock arm records the live label, not a literal"
fi

printf '== the stock reuse check reads the recorded Engram label ==\n'
if [ -z "$CHECK_PY" ]; then
    skip "the reuse check (no python3 on PATH)"
else
    STOCK_DIR="$MODELS_OUT/src-oQ4e-stock"
    mkdir -p "$STOCK_DIR"
    printf '{}\n' > "$STOCK_DIR/quantization_report.json"
    # The script records its --src after `cd && pwd`, which collapses the double
    # slash macOS puts in $TMPDIR; the fixture has to agree or the src term, not
    # the Engram label, is what mismatches.
    SRC_CANON="$(cd "$SRC" && pwd)"
    write_stock_build() { # <ngram-label>
        cat > "$STOCK_DIR/build.json" <<JSON
{
  "family": "deepseek_v41",
  "src": "$SRC_CANON",
  "oq_level": 4,
  "preserve_mtp": 1,
  "omlx_commit": "",
  "calib_dataset_intent": "stock-default",
  "ngram_bits": "$1"
}
JSON
    }
    write_stock_build "8"
    dry_run_env omlx_deepseek_v41_oq4e.sh t2-stale OQ_SKIP_STOCK=0 VENV_PY="$CHECK_PY"
    assert_says "a stock build at another Engram label is stale" "$WORK/t2-stale.out" \
        "stock reuse check: STALE"
    write_stock_build "preserved"
    dry_run_env omlx_deepseek_v41_oq4e.sh t2-current OQ_SKIP_STOCK=0 VENV_PY="$CHECK_PY"
    assert_says "a stock build at the live label is reusable" "$WORK/t2-current.out" \
        "stock reuse check: OK"
    assert_exit "the reuse check does not abort the run" 0 "$DRY_EXIT"
fi

printf '== the run lock is owned, not decorative ==\n'
# A live pid stands in for a build that is hours into a ~200 GB quant. No
# invocation may delete that owner's lock, and the lock has to be held before
# anything destructive runs, so the stock arm is exercised with a fake venv
# python that records what it sees when it is launched.
sleep 300 &
LIVE_PID=$!
OQ4E=scripts/omlx_deepseek_v41_oq4e.sh
pid_holds_pid() { # <pidfile> <pid>
    [ -f "$1" ] && [ "$(cat "$1" 2>/dev/null)" = "$2" ]
}

# 1. A dry run is a read: it claims no lock, so it cannot free the lock of the
#    build that is actually running.
LIVE_PIDFILE="$OQUP/oq4e-t2-lock-dry.pid"
printf '%s\n' "$LIVE_PID" > "$LIVE_PIDFILE"
dry_run omlx_deepseek_v41_oq4e.sh t2-lock-dry
assert_exit "a dry run succeeds while another build holds the version lock" 0 "$DRY_EXIT"
if pid_holds_pid "$LIVE_PIDFILE" "$LIVE_PID"; then
    pass "a dry run leaves the live version pidfile alone"
else
    fail "a dry run leaves the live version pidfile alone ($(cat "$LIVE_PIDFILE" 2>/dev/null || echo "it was deleted"))"
fi

# 2. A duplicate real run is refused, and the refusal is not allowed to release
#    the owner's lock on its way out.
mkdir -p "$MODELS_OUT/src-oQ4e-t2-lock-real"
LIVE_PIDFILE2="$OQUP/oq4e-t2-lock-real.pid"
printf '%s\n' "$LIVE_PID" > "$LIVE_PIDFILE2"
( cd "$REPO" && bash "$OQ4E" t2-lock-real --src "$SRC" ) > "$WORK/t2-lock-real.out" 2>&1
DUP_EXIT=$?
assert_exit "a duplicate run of a live version is refused" 1 "$DUP_EXIT"
assert_says "the refusal names the running build" "$WORK/t2-lock-real.out" "already running"
if pid_holds_pid "$LIVE_PIDFILE2" "$LIVE_PID"; then
    pass "a refused run leaves the live version pidfile alone"
else
    fail "a refused run leaves the live version pidfile alone ($(cat "$LIVE_PIDFILE2" 2>/dev/null || echo "it was deleted"))"
fi

# 3. The lock must already be held when the stock arm launches: that arm can
#    take hours, and a second invocation that arrives inside it would otherwise
#    see no lock at all.
FAKE_PY="$WORK/fake-venv-python.sh"
cat > "$FAKE_PY" <<FAKE
#!/usr/bin/env bash
# Stand-in for the MLX venv python. The stock-reuse check is a stdin script
# and needs real json, so '-' runs the real interpreter; a runner launch only
# records whether this version's lock was already held at launch time.
if [ "\$1" = "-" ]; then exec $CHECK_PY "\$@"; fi
if [ -n "\${LOCK_PROBE_FILE:-}" ] && [ -f "\${LOCK_PROBE_FILE}" ]; then
    echo "lock at launch: held pid=\$(cat "\$LOCK_PROBE_FILE")"
else
    echo "lock at launch: none"
fi
exit 1
FAKE
chmod +x "$FAKE_PY"

# The stock arm only rebuilds when the reuse check says stale, so the fixture
# carries metadata with a label this run does not use.
STOCK_LIVE_DIR="$MODELS_OUT/src-oQ4e-stock"
SRC_CANON="$(cd "$SRC" && pwd)"
if [ -z "$CHECK_PY" ]; then
    skip "the version lock during the stock arm (no python3 on PATH)"
    skip "a refused stock arm never deletes a live stock output (no python3 on PATH)"
    skip "a refused stock arm leaves the live stock pidfile alone (no python3 on PATH)"
    skip "the stock refusal names the running stock build (no python3 on PATH)"
else
    mkdir -p "$STOCK_LIVE_DIR"
    printf '{}\n' > "$STOCK_LIVE_DIR/quantization_report.json"
    cat > "$STOCK_LIVE_DIR/build.json" <<JSON
{
  "family": "deepseek_v41",
  "src": "$SRC_CANON",
  "oq_level": 4,
  "preserve_mtp": 1,
  "omlx_commit": "",
  "calib_dataset_intent": "stock-default",
  "ngram_bits": "8"
}
JSON
    rm -f "$OQUP/oq4e-src-stock.pid"
    ( cd "$REPO" && env VENV_PY="$FAKE_PY" OQ_SKIP_STOCK=0 \
        LOCK_PROBE_FILE="$OQUP/oq4e-t2-lock-order.pid" \
        bash "$OQ4E" t2-lock-order --src "$SRC" ) > "$WORK/t2-lock-order.out" 2>&1
    assert_says "the version lock is held before the stock arm launches" \
        "$OQUP/oq4e-src-stock.log" "lock at launch: held"

    # 4. The stock output is shared by every version of the same model and
    #    level, so it needs a lock of its own: the loser must leave it alone.
    rm -rf "$STOCK_LIVE_DIR"
    mkdir -p "$STOCK_LIVE_DIR"
    printf 'do not touch\n' > "$STOCK_LIVE_DIR/model-00001-of-00001.safetensors"
    printf '%s\n' "$LIVE_PID" > "$OQUP/oq4e-src-stock.pid"
    ( cd "$REPO" && env VENV_PY="$FAKE_PY" OQ_SKIP_STOCK=0 \
        bash "$OQ4E" t2-lock-stock --src "$SRC" ) > "$WORK/t2-lock-stock.out" 2>&1
    if [ -f "$STOCK_LIVE_DIR/model-00001-of-00001.safetensors" ]; then
        pass "a refused stock arm never deletes a live stock output"
    else
        fail "a refused stock arm never deletes a live stock output (the directory was wiped)"
    fi
    if pid_holds_pid "$OQUP/oq4e-src-stock.pid" "$LIVE_PID"; then
        pass "a refused stock arm leaves the live stock pidfile alone"
    else
        fail "a refused stock arm leaves the live stock pidfile alone ($(cat "$OQUP/oq4e-src-stock.pid" 2>/dev/null || echo "it was deleted"))"
    fi
    assert_says "the stock refusal names the running stock build" "$WORK/t2-lock-stock.out" "already running"
fi

# 5. A lock left by a crash must not block the version forever. The stand-in
# quantizer always fails, so what is checked is that the run gets past the lock.
sleep 0.2 &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
STALE_PIDFILE="$OQUP/oq4e-t2-lock-stale.pid"
printf '%s\n' "$DEAD_PID" > "$STALE_PIDFILE"
( cd "$REPO" && bash "$OQ4E" t2-lock-stale --src "$SRC" ) > "$WORK/t2-lock-stale.out" 2>&1
if grep -qF "already running" "$WORK/t2-lock-stale.out"; then
    fail "a stale pidfile is reclaimed (the run was refused)"
else
    pass "a stale pidfile is reclaimed"
fi
assert_says "reclaiming says so" "$WORK/t2-lock-stale.out" "stale pidfile"
if [ -e "$STALE_PIDFILE" ]; then
    fail "a finished run releases its lock ($STALE_PIDFILE survives)"
else
    pass "a finished run releases its lock"
fi
kill "$LIVE_PID" 2>/dev/null
wait "$LIVE_PID" 2>/dev/null
LIVE_PID=""

printf '== summary ==\n'
if [ "$FAILURES" -eq 0 ]; then
    echo "PASS"
    exit 0
fi
echo "FAIL ($FAILURES)"
exit 1
