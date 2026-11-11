#!/bin/bash
set -euo pipefail
src=${1:?usage: backup.sh SRC DEST}
dest=${2:?usage: backup.sh SRC DEST}
if [ ! -d "$dest" ]; then
  echo "backup: destination $dest does not exist" >&2
  exit 1
fi
for f in "$src"/*; do
  [ -f "$f" ] || continue
  cp -- "$f" "$dest/"
done
echo "backed up"
