#!/bin/bash
set -euo pipefail
log=${1:?usage: summarize.sh LOGFILE}
skipped=0
valid="$(mktemp)"
trap 'rm -f "$valid"' EXIT
while IFS= read -r line; do
  if printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
    printf '%s\n' "$line" >> "$valid"
  else
    skipped=$((skipped + 1))
  fi
done < "$log"
jq -rs 'group_by(.route)[] | [.[0].route, length, (map(select(.status >= 500)) | length), (map(.ms) | max)] | @tsv' "$valid"
echo "skipped $skipped" >&2
