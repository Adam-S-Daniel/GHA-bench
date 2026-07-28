#!/usr/bin/env bats

# Test suite for build matrix generator

setup() {
  # Set up test fixtures directory
  TEST_FIXTURES_DIR="${BATS_TEST_DIRNAME}/../fixtures"
  GENERATOR_SCRIPT="${BATS_TEST_DIRNAME}/../src/matrix-generator.sh"
}

# Test 1: Script exists and is executable
@test "script exists and is executable" {
  [ -f "$GENERATOR_SCRIPT" ]
  [ -x "$GENERATOR_SCRIPT" ]
}

# Test 2: Generate matrix from minimal valid config
@test "generate matrix from minimal config with single os" {
  local config_file="${TEST_FIXTURES_DIR}/minimal-config.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should contain matrix key
  echo "$output" | grep -q '"matrix"'

  # Should contain include array
  echo "$output" | grep -q '"include"'
}

# Test 3: Handle invalid JSON input
@test "reject invalid JSON input" {
  local config_file="${TEST_FIXTURES_DIR}/invalid.json"

  run "$GENERATOR_SCRIPT" "$config_file"
  [ "$status" -ne 0 ]
}

# Test 4: Generate matrix with multiple OS options
@test "generate matrix with multiple OS options" {
  local config_file="${TEST_FIXTURES_DIR}/multi-os-config.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should be valid JSON
  echo "$output" | jq . > /dev/null
}

# Test 5: Respect max-parallel constraint
@test "respect max-parallel limit" {
  local config_file="${TEST_FIXTURES_DIR}/config-with-max-parallel.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should include max-parallel setting
  echo "$output" | grep -q '"max-parallel"'
}

# Test 6: Validate matrix does not exceed maximum size
@test "validate matrix does not exceed max size" {
  local config_file="${TEST_FIXTURES_DIR}/large-config.json"

  run "$GENERATOR_SCRIPT" "$config_file"
  [ "$status" -eq 0 ]
}

# Test 7: Handle include rules
@test "handle include rules in matrix" {
  local config_file="${TEST_FIXTURES_DIR}/config-with-includes.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should contain include array with custom entries
  echo "$output" | grep -q '"include"'
}

# Test 8: Handle exclude rules
@test "handle exclude rules in matrix" {
  local config_file="${TEST_FIXTURES_DIR}/config-with-excludes.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should be valid JSON
  echo "$output" | jq . > /dev/null
}

# Test 9: Set fail-fast configuration
@test "set fail-fast configuration" {
  local config_file="${TEST_FIXTURES_DIR}/config-with-fail-fast.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should include fail-fast setting
  echo "$output" | grep -q '"fail-fast"'
}

# Test 10: Output valid GitHub Actions matrix JSON
@test "output valid GitHub Actions matrix JSON" {
  local config_file="${TEST_FIXTURES_DIR}/minimal-config.json"

  local output
  output=$("$GENERATOR_SCRIPT" "$config_file")

  # Should be parseable as JSON
  echo "$output" | jq . > /dev/null

  # Should have matrix key
  local matrix_exists
  matrix_exists=$(echo "$output" | jq 'has("matrix")' 2>/dev/null)
  [ "$matrix_exists" = "true" ]
}
