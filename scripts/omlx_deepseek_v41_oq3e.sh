#!/usr/bin/env bash
# omlx_deepseek_v41_oq3e.sh — oQ3e variant of omlx_deepseek_v41_oq4e.sh.
#
# Thin wrapper: all logic lives in omlx_deepseek_v41_oq4e.sh. V4.1 oQ3
# streams one decoder block at a time by default and keeps the Engram table
# at Q8 for comparability across the series. This is the middle point between
# oQ2.5e (largest corpus effect) and oQ4e (no projection requantization).
#
# Usage: scripts/omlx_deepseek_v41_oq3e.sh [<org/model>] <version> [ngram_bits] [--src <dir>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OQ_LEVEL=3 NGRAM_BITS=8 exec "$SCRIPT_DIR/omlx_deepseek_v41_oq4e.sh" "$@"
