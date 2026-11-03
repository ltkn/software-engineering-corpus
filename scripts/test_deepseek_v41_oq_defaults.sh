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
cleanup() { rm -rf "$WORK"; }
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

printf '== summary ==\n'
if [ "$FAILURES" -eq 0 ]; then
    echo "PASS"
    exit 0
fi
echo "FAIL ($FAILURES)"
exit 1
