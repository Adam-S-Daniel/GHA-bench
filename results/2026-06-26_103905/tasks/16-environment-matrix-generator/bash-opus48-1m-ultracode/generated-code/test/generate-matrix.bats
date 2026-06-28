#!/usr/bin/env bats
#
# Unit tests for generate-matrix.sh — drives the red/green TDD of the script
# logic directly (fast: milliseconds per case). The end-to-end acceptance tests
# that exercise the *workflow* through `act` live in test/workflow.bats.

setup() {
  # Resolve paths relative to the test file so tests work from any CWD.
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/generate-matrix.sh"
  FIXTURES="$PROJECT_ROOT/fixtures"
}

# --- Cycle 1: basic cartesian product ---------------------------------------

@test "basic config produces the full cartesian product as matrix.include" {
  run "$SCRIPT" "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  # 2 OS x 2 node versions = 4 combinations
  echo "$output" | jq -e '.size == 4'
  echo "$output" | jq -e '.matrix.include | length == 4'
  echo "$output" | jq -e 'any(.matrix.include[]; .os == "ubuntu-latest" and .node == "18")'
  echo "$output" | jq -e 'any(.matrix.include[]; .os == "windows-latest" and .node == "20")'
}

@test "fail-fast defaults to true and output is valid JSON" {
  run "$SCRIPT" "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["fail-fast"] == true'
  # An absent max-parallel must be omitted, not null.
  echo "$output" | jq -e 'has("max-parallel") == false'
}

# --- Cycle 2: exclude / include / passthrough -------------------------------

@test "exclude removes only the combinations matching all listed keys" {
  run "$SCRIPT" "$FIXTURES/exclude.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.size == 5'
  # macos-latest + node 18 is excluded ...
  echo "$output" | jq -e 'any(.matrix.include[]; .os == "macos-latest" and .node == "18") | not'
  # ... but macos-latest + node 20 survives.
  echo "$output" | jq -e 'any(.matrix.include[]; .os == "macos-latest" and .node == "20")'
}

@test "max-parallel and fail-fast=false are passed through verbatim" {
  run "$SCRIPT" "$FIXTURES/exclude.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.["max-parallel"] == 3'
  echo "$output" | jq -e '.["fail-fast"] == false'
}

@test "include follows GitHub Actions merge semantics exactly" {
  run "$SCRIPT" "$FIXTURES/include.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.size == 6'
  # apple+cat gets color pink (overriding the earlier green) and shape circle.
  echo "$output" | jq -e 'any(.matrix.include[];
    .fruit=="apple" and .animal=="cat" and .color=="pink" and .shape=="circle")'
  # apple+dog keeps color green and gains shape circle.
  echo "$output" | jq -e 'any(.matrix.include[];
    .fruit=="apple" and .animal=="dog" and .color=="green" and .shape=="circle")'
  # banana entries become brand-new standalone combinations.
  echo "$output" | jq -e 'any(.matrix.include[];
    .fruit=="banana" and (has("animal")|not))'
  echo "$output" | jq -e 'any(.matrix.include[];
    .fruit=="banana" and .animal=="cat")'
}

@test "include-only config (no dimensions) yields one combination per entry" {
  run "$SCRIPT" "$FIXTURES/include-only.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.size == 2'
  echo "$output" | jq -e 'any(.matrix.include[]; .os=="ubuntu-latest" and .node=="18")'
  echo "$output" | jq -e 'any(.matrix.include[]; .os=="windows-latest" and .node=="20")'
}

@test "a matrix within max-size passes validation" {
  run "$SCRIPT" "$FIXTURES/limit.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.size == 6'
}

# --- Cycle 3: error handling ------------------------------------------------

@test "exceeding max-size fails with exit code 2 and a clear message" {
  run "$SCRIPT" "$FIXTURES/oversize.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"matrix size 16 exceeds maximum 10"* ]]
}

@test "a missing config file exits 1 with a meaningful message" {
  run "$SCRIPT" "$FIXTURES/does-not-exist.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "invalid JSON exits 1" {
  run bash -c "printf '%s' '{not json' | '$SCRIPT' -"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "an empty config (no dimensions or include) exits 1" {
  run bash -c "printf '%s' '{}' | '$SCRIPT' -"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-empty 'dimensions'"* ]]
}

@test "a non-boolean fail-fast exits 1" {
  run bash -c "printf '%s' '{\"dimensions\":{\"a\":[\"1\"]},\"fail-fast\":\"yes\"}' | '$SCRIPT' -"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'fail-fast' must be a boolean"* ]]
}

@test "a non-positive max-parallel exits 1" {
  run bash -c "printf '%s' '{\"dimensions\":{\"a\":[\"1\"]},\"max-parallel\":0}' | '$SCRIPT' -"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'max-parallel' must be a positive integer"* ]]
}

@test "an empty dimension array exits 1" {
  run bash -c "printf '%s' '{\"dimensions\":{\"a\":[]}}' | '$SCRIPT' -"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a non-empty array"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

