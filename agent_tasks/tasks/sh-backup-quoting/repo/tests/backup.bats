bats_require_minimum_version 1.5.0

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/src" "$WORK/dest"
  printf 'a' > "$WORK/src/plain.txt"
  printf 'b' > "$WORK/src/with space.txt"
  printf 'c' > "$WORK/src/-dash.txt"
}
teardown() { rm -rf "$WORK"; }

@test "copies every file with its name" {
  run bash ./backup.sh "$WORK/src" "$WORK/dest"
  [ "$status" -eq 0 ]
  [ -f "$WORK/dest/plain.txt" ]
  [ -f "$WORK/dest/with space.txt" ]
  [ -f "$WORK/dest/-dash.txt" ]
}

@test "fails when destination is missing" {
  run bash ./backup.sh "$WORK/src" "$WORK/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
