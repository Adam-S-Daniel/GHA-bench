#!/usr/bin/env bats
# TDD: same normalized TSV contract as parse_junit.sh, driven by jq over our
# simple {"tests":[{"name","status","duration"}]} schema.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PARSE_JSON="$ROOT_DIR/lib/parse_json.sh"
  FIXTURES="$ROOT_DIR/fixtures"
}

@test "parse_json emits one TSV row per test with correct status" {
  run "$PARSE_JSON" "$FIXTURES/json_sample.json"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  echo "$output" | grep -qF "$(printf 'test_login\tpassed\t0.15')"
  echo "$output" | grep -qF "$(printf 'test_logout\tfailed\t0.05')"
  echo "$output" | grep -qF "$(printf 'test_ssr_render\tskipped\t0')"
}

@test "parse_json prefixes each row with source file name" {
  run "$PARSE_JSON" "$FIXTURES/json_sample.json"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "json_sample.json"
}

@test "parse_json fails with meaningful error on missing file" {
  run "$PARSE_JSON" "$FIXTURES/does_not_exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse_json fails with meaningful error on malformed JSON" {
  run "$PARSE_JSON" "$FIXTURES/json_malformed.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"parse"* ]]
}
