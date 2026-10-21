#!/usr/bin/env bash
# omlx_deepseek_v41_oq25e.sh — oQ2.5e variant of omlx_deepseek_v41_oq4e.sh.
#
# Thin wrapper: all logic lives in omlx_deepseek_v41_oq4e.sh. V4.1 oQ2.5
# streams one decoder block at a time by default and keeps the Engram table
# at Q8 for comparability across the series. At oQ2.5 the quantization error
# is largest, so this is where the custom-vs-generic corpus delta should be
# easiest to see.
#
# Usage: scripts/omlx_deepseek_v41_oq25e.sh [<org/model>] <version> [ngram_bits] [--src <dir>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OQ_LEVEL=2.5 NGRAM_BITS=8 exec "$SCRIPT_DIR/omlx_deepseek_v41_oq4e.sh" "$@"
