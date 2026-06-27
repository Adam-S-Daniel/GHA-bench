#!/usr/bin/env bats
#
# Tests for artifact-cleanup.sh — drive development red/green TDD style.
#
# The script reads a TSV file of artifacts and applies retention policies,
# producing a deterministic deletion plan + summary. A fixed --now epoch is
# always supplied so the "max age" policy is reproducible in CI.

setup() {
  # Absolute path to the script under test (one dir up from tests/).
  SCRIPT="${BATS_TEST_DIRNAME}/../artifact-cleanup.sh"
  # A scratch dir for per-test fixtures.
  TMP="$(mktemp -d)"
  # Reference "now" used across tests: 2026-06-26T00:00:00Z = 1782432000.
  NOW=1782432000
}

teardown() {
  rm -rf "$TMP"
}

# Helper: write a TSV fixture. Columns: name<TAB>size_bytes<TAB>created_epoch<TAB>run_id
make_fixture() {
  printf '%s\n' "$@" > "$TMP/artifacts.tsv"
}

@test "exits non-zero and prints usage when no input file is given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "errors when the input file does not exist" {
  run "$SCRIPT" --input "$TMP/missing.tsv" --now "$NOW"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ----- Core parsing / plan tests -----------------------------------------
# Fixture artifacts relative to NOW (1 day = 86400s):
#   a  run=1  age=10d  size=100   created=1781568000
#   b  run=1  age= 5d  size=200   created=1782000000
#   c  run=2  age=40d  size=300   created=1778976000

@test "with no policies every artifact is kept and nothing is reclaimed" {
  make_fixture \
    $'a\t100\t1781568000\t1' \
    $'b\t200\t1782000000\t1' \
    $'c\t300\t1778976000\t2'
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total artifacts: 3"* ]]
  [[ "$output" == *"Retained: 3"* ]]
  [[ "$output" == *"Deleted: 0"* ]]
  [[ "$output" == *"Space reclaimed: 0 bytes"* ]]
}

@test "max-age-days deletes artifacts older than the threshold" {
  make_fixture \
    $'a\t100\t1781568000\t1' \
    $'b\t200\t1782000000\t1' \
    $'c\t300\t1778976000\t2'
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW" --max-age-days 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE"*"c"*"max-age"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 300 bytes"* ]]
}

@test "keep-latest keeps the N newest artifacts per workflow run id" {
  make_fixture \
    $'a\t100\t1781568000\t1' \
    $'b\t200\t1782000000\t1' \
    $'c\t300\t1778976000\t2'
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW" --keep-latest 1
  [ "$status" -eq 0 ]
  # run 1: b is newer than a -> a deleted; run 2: c is the only one -> kept.
  [[ "$output" == *"DELETE"*"a"*"keep-latest"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 100 bytes"* ]]
}

@test "max-total-size deletes oldest survivors until total fits" {
  make_fixture \
    $'a\t100\t1781568000\t1' \
    $'b\t200\t1782000000\t1' \
    $'c\t300\t1778976000\t2'
  # Total is 600; cap at 350 -> drop oldest (c, 300) leaving 300.
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW" --max-total-size 350
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELETE"*"c"*"max-total-size"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 300 bytes"* ]]
}

@test "dry-run mode is clearly marked in the plan header" {
  make_fixture $'a\t100\t1781568000\t1'
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "policies combine: an artifact deleted by age is counted once" {
  make_fixture \
    $'a\t100\t1781568000\t1' \
    $'b\t200\t1782000000\t1' \
    $'c\t300\t1778976000\t2'
  # age>30 deletes c; keep-latest 1 deletes a; b survives.
  run "$SCRIPT" --input "$TMP/artifacts.tsv" --now "$NOW" \
      --max-age-days 30 --keep-latest 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retained: 1"* ]]
  [[ "$output" == *"Deleted: 2"* ]]
  [[ "$output" == *"Space reclaimed: 400 bytes"* ]]
}

@test "malformed line (wrong column count) is reported as an error" {
  printf 'a\t100\tonly-three-cols\n' > "$TMP/bad.tsv"
  run "$SCRIPT" --input "$TMP/bad.tsv" --now "$NOW"
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed"* ]]
}
