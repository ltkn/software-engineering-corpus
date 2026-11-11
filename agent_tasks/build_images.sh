#!/usr/bin/env bash
# build_images.sh — build the sandbox images the agent tasks use (needs network once).
#   agent_tasks/build_images.sh            build missing images
#   agent_tasks/build_images.sh --rebuild  rebuild all
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REBUILD=0; [ "${1:-}" = "--rebuild" ] && REBUILD=1
for dir in "$HERE"/images/*/; do
    name="oqt-agent-$(basename "$dir")"
    if [ "$REBUILD" = 0 ] && docker image inspect "$name" >/dev/null 2>&1; then
        echo "ok    $name (already built)"
        continue
    fi
    echo "build $name"
    docker build -q -t "$name" "$dir" >/dev/null
done
