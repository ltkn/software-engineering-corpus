#!/usr/bin/env bash
# omlx_oq5e.sh — oQ5e variant of omlx_oq4e.sh (same custom corpus, Q5 trunk).
#
# Thin wrapper: all logic lives in omlx_oq4e.sh. At oQ5 the quantization
# error floor is much lower, so expect a smaller custom-vs-generic corpus
# delta than at oQ4e — this run measures exactly that.
#
# Usage: scripts/omlx_oq5e.sh <version> [--src <dir>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OQ_LEVEL=5 NGRAM_BITS=8 exec "$SCRIPT_DIR/omlx_oq4e.sh" "$@"
