bats_require_minimum_version 1.5.0

setup() {
  LOG="$(mktemp)"
  cat > "$LOG" <<'EOF'
{"route":"GET /users","status":200,"ms":41}
{"route":"POST /orders","status":503,"ms":1200}
not json
{"route":"GET /users","status":500,"ms":90}
{"route":"POST /orders","status":201,"ms":300}
EOF
}
teardown() { rm -f "$LOG"; }

@test "per-route summary" {
  run --separate-stderr bash ./summarize.sh "$LOG"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'GET /users\t2\t1\t90' ]
  [ "${lines[1]}" = $'POST /orders\t2\t1\t1200' ]
  [[ "$stderr" == *"skipped 1"* ]]
}
