#!/usr/bin/env bash
# build_images.sh — build the sandbox images the agent tasks use (needs network once).
#   agent_tasks/build_images.sh            build missing or changed images
#   agent_tasks/build_images.sh --rebuild  rebuild all
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REBUILD=0; [ "${1:-}" = "--rebuild" ] && REBUILD=1
for dir in "$HERE"/images/*/; do
    name="oqt-agent-$(basename "$dir")"
    # The image carries a hash of its folder, so a changed Dockerfile or warmup rebuilds it.
    want="$(cd "$dir" && find . -type f ! -name '*.iml' | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16)"
    have="$(docker image inspect -f '{{index .Config.Labels "oqt.src"}}' "$name" 2>/dev/null || true)"
    if [ "$REBUILD" = 0 ] && [ "$have" = "$want" ]; then
        echo "ok    $name (up to date)"
        continue
    fi
    echo "build $name${have:+ (its source changed)}"
    docker build -q --label "oqt.src=$want" -t "$name" "$dir" >/dev/null
done
