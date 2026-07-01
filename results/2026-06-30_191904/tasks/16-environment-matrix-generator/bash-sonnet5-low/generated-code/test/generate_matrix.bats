#!/usr/bin/env bats
# Tests for generate_matrix.sh — GitHub Actions build matrix generator.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../generate_matrix.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# --- Basic cartesian product ---

@test "generates a plain cartesian product of os x versions" {
  run "$SCRIPT" "$FIXTURES/simple_config.json"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.matrix.include | length')
  [ "$count" -eq 4 ]
}

@test "cartesian product contains expected combination" {
  run "$SCRIPT" "$FIXTURES/simple_config.json"
  [ "$status" -eq 0 ]
  found=$(echo "$output" | jq '[.matrix.include[] | select(.os=="ubuntu-latest" and .versions=="16")] | length')
  [ "$found" -eq 1 ]
}

@test "fail-fast flag is passed through" {
  run "$SCRIPT" "$FIXTURES/simple_config.json"
  [ "$status" -eq 0 ]
  ff=$(echo "$output" | jq '.["fail-fast"]')
  [ "$ff" = "true" ]
}

# --- Feature flags as an extra dimension ---

@test "feature flags add an extra matrix dimension" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  # os(3) x versions(3) x experimental(2) = 18, plus 1 include - 2 excludes (one exclude removes 3 combos)
  has_exp=$(echo "$output" | jq '[.matrix.include[] | select(has("experimental"))] | length > 0')
  [ "$has_exp" = "true" ]
}

# --- Include rules ---

@test "include rule adds an extra combination" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  found=$(echo "$output" | jq '[.matrix.include[] | select(.os=="ubuntu-latest" and .versions=="21" and .experimental==true)] | length')
  [ "$found" -eq 1 ]
}

# --- Exclude rules ---

@test "exclude rule removes matching combinations" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  found=$(echo "$output" | jq '[.matrix.include[] | select(.os=="windows-latest" and .versions=="16")] | length')
  [ "$found" -eq 0 ]
}

@test "exclude rule with partial keys removes all matching combos" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  found=$(echo "$output" | jq '[.matrix.include[] | select(.os=="macos-latest" and .experimental==true)] | length')
  [ "$found" -eq 0 ]
}

# --- max-parallel ---

@test "fail_fast false is preserved (not coerced to true)" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  ff=$(echo "$output" | jq '.["fail-fast"]')
  [ "$ff" = "false" ]
}

@test "max-parallel is included in output when set" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  mp=$(echo "$output" | jq '.["max-parallel"]')
  [ "$mp" -eq 4 ]
}

# --- max size validation ---

@test "fails with meaningful error when matrix exceeds max_size" {
  run "$SCRIPT" "$FIXTURES/oversized_config.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exceeds maximum"* ]]
}

# --- Input validation ---

@test "fails with meaningful error when os is missing" {
  run "$SCRIPT" "$FIXTURES/invalid_config.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"os"* ]]
}

@test "fails with meaningful error when config file does not exist" {
  run "$SCRIPT" "$FIXTURES/does_not_exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "fails with meaningful error when no arguments are given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "output is valid JSON" {
  run "$SCRIPT" "$FIXTURES/full_config.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}
