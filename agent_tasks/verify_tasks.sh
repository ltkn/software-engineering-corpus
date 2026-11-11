#!/usr/bin/env bash
# verify_tasks.sh — every task must FAIL as shipped and PASS with its reference
# solution, inside its own sandbox image with no network.
#   agent_tasks/verify_tasks.sh [task-id ...]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "$HOME/.oqt-verify.XXXXXX")"   # under $HOME so colima can mount it
trap 'rm -rf "$WORK"' EXIT
bad=0
for tdir in "$HERE"/tasks/*/; do
    id="$(basename "$tdir")"
    if [ $# -gt 0 ] && [[ " $* " != *" $id "* ]]; then continue; fi
    image="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["image"])' "$tdir/task.json")"
    check="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["check"])' "$tdir/task.json")"
    # A hung check must fail, not stall the verification (timeout runs inside the image).
    run_check() { docker run --rm --network none -v "$1:/work" -w /work "$image" \
                      timeout 300 sh -c "$check" >"$1.log" 2>&1; }
    # Fresh, unique folders per run: re-using one path lets the VM's file sharing
    # serve a stale view of the previous task.
    a="$WORK/$id-shipped"; b="$WORK/$id-solved"
    cp -R "$tdir/repo" "$a"; cp -R "$tdir/repo" "$b"; cp -R "$tdir/solution/." "$b/"
    if run_check "$a"; then shipped=PASS; else shipped=fail; fi
    if run_check "$b"; then solved=PASS; else solved=fail; fi
    if [ "$shipped" = fail ] && [ "$solved" = PASS ]; then
        echo "ok    $id"
    else
        echo "BAD   $id (as shipped: $shipped, with solution: $solved)"; tail -n 15 "$b.log" | sed 's/^/      /'
        bad=1
    fi
done
exit $bad
