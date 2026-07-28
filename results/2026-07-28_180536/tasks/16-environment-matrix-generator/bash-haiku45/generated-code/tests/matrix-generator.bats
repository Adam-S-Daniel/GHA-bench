#!/usr/bin/env bats

# Test setup: source the script before each test
setup() {
  cd "${BATS_TEST_DIRNAME}/.."
}

# Test 1: Script exists and is executable
@test "matrix-generator script exists" {
  [ -f "./matrix-generator.sh" ]
}

@test "matrix-generator script is executable" {
  [ -x "./matrix-generator.sh" ]
}

# Test 2: Simple matrix with single OS
@test "generates matrix with single OS" {
  local input='{"os": ["ubuntu-latest"], "node": ["20"]}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Output should be valid JSON
  echo "$output" | jq . > /dev/null

  # Should contain expected values
  echo "$output" | jq '.include[0].os' | grep -q "ubuntu-latest"
  echo "$output" | jq '.include[0].node' | grep -q "20"
}

# Test 3: Matrix with multiple values
@test "generates matrix with multiple OS and node versions" {
  local input='{"os": ["ubuntu-latest", "macos-latest"], "node": ["18", "20"]}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have 4 combinations
  local count
  count=$(echo "$output" | jq '.include | length')
  [ "$count" -eq 4 ]
}

# Test 4: Respects max-parallel limit
@test "respects max-parallel configuration" {
  local input='{"os": ["ubuntu-latest"], "node": ["20"], "max-parallel": 2}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have max-parallel key
  echo "$output" | jq '.["max-parallel"]' | grep -q "2"
}

# Test 5: Respects fail-fast configuration
@test "respects fail-fast configuration" {
  local input='{"os": ["ubuntu-latest"], "node": ["20"], "fail-fast": false}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have fail-fast key set to false
  echo "$output" | jq '.["fail-fast"]' | grep -q "false"
}

# Test 6: Supports exclude rules
@test "supports exclude rules" {
  local input='{"os": ["ubuntu-latest", "macos-latest"], "node": ["18", "20"], "exclude": [{"os": "macos-latest", "node": "18"}]}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have exclude key
  echo "$output" | jq '.exclude' | jq length | grep -q "1"
  echo "$output" | jq '.exclude[0].os' | grep -q "macos-latest"
}

# Test 7: Supports include rules
@test "supports include rules (override)" {
  local input='{"os": ["ubuntu-latest"], "node": ["20"], "include": [{"os": "windows-latest", "node": "20", "experimental": true}]}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have include key with additional entry
  echo "$output" | jq '.include | map(select(.os == "windows-latest")) | length' | grep -q "1"
}

# Test 8: Validates matrix size doesn't exceed maximum
@test "rejects matrix exceeding max size" {
  local input='{"os": ["ubuntu-latest", "macos-latest"], "node": ["18", "20", "22"], "max-size": 5}'
  # This would create 6 combinations (2 os * 3 nodes), exceeding max-size of 5

  output=$(echo "$input" | ./matrix-generator.sh 2>&1) || true

  # Should exit with non-zero and show error
  [ $? -ne 0 ] || echo "$output" | grep -q "exceeds maximum"
}

# Test 9: Default fail-fast is true
@test "fail-fast defaults to true" {
  local input='{"os": ["ubuntu-latest"], "node": ["20"]}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should have fail-fast set to true by default
  echo "$output" | jq '.["fail-fast"]' | grep -q "true"
}

# Test 10: Empty configuration returns valid matrix
@test "handles minimal configuration" {
  local input='{}'
  local output
  output=$(echo "$input" | ./matrix-generator.sh)

  # Should be valid JSON
  echo "$output" | jq . > /dev/null
}
