#!/usr/bin/env bats
# TDD step 1: define expected normalized TSV output (file, testname, status, duration)
# before writing any parsing logic in lib/parse_junit.sh.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PARSE_JUNIT="$ROOT_DIR/lib/parse_junit.sh"
  FIXTURES="$ROOT_DIR/fixtures"
}

@test "parse_junit emits one TSV row per testcase with correct status" {
  run "$PARSE_JUNIT" "$FIXTURES/junit_sample.xml"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  echo "$output" | grep -qF "$(printf 'test_addition\tpassed\t0.010')"
  echo "$output" | grep -qF "$(printf 'test_division\tfailed\t0.020')"
  echo "$output" | grep -qF "$(printf 'test_legacy\tskipped\t0.005')"
}

@test "parse_junit prefixes each row with the source file name" {
  run "$PARSE_JUNIT" "$FIXTURES/junit_sample.xml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "junit_sample.xml"
}

@test "parse_junit fails with meaningful error on missing file" {
  run "$PARSE_JUNIT" "$FIXTURES/does_not_exist.xml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"No such file"* ]]
}

@test "parse_junit fails with meaningful error on malformed XML" {
  run "$PARSE_JUNIT" "$FIXTURES/junit_malformed.xml"
  [ "$status" -ne 0 ]
}
