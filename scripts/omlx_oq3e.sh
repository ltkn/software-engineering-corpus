#!/usr/bin/env bash
# omlx_oq3e.sh — oQ3e variant of omlx_oq4e.sh (same custom corpus, Q3 trunk).
#
# Thin wrapper: all logic lives in omlx_oq4e.sh. At oQ3 the quantization
# error is largest, so expect the biggest custom-vs-generic corpus delta
# here — the mirror image of oQ5e. N-gram table stays Q8 for comparability
# across the 3e/4e/5e series.
#
# Usage: scripts/omlx_oq3e.sh <version> [--src <dir>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OQ_LEVEL=3 NGRAM_BITS=8 exec "$SCRIPT_DIR/omlx_oq4e.sh" "$@"
