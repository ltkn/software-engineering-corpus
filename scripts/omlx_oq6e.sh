#!/usr/bin/env bash
# omlx_oq6e.sh — oQ6e variant of omlx_oq4e.sh (same custom corpus, Q6 trunk).
#
# Thin wrapper: all logic lives in omlx_oq4e.sh. At oQ6 the quantization
# error floor is very low, so expect the custom-vs-generic corpus delta to
# approach zero — this level is the reference/premium tier, not the corpus
# thesis (oQ3e/oQ4e carry that). Memory note for 128 GB hosts: the Q8
# N-gram table never fits alongside the Q6 trunk, so serving mmap's it
# regardless of NGRAM_BITS.
#
# Usage: scripts/omlx_oq6e.sh [<org/model>] <version> [ngram_bits] [--src <dir>] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OQ_LEVEL=6 NGRAM_BITS=8 exec "$SCRIPT_DIR/omlx_oq4e.sh" "$@"
