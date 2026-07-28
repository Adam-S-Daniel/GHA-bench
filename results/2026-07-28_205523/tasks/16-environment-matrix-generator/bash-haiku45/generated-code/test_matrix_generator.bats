#!/usr/bin/env bats

# Test suite for environment-matrix-generator.sh
# Uses bats-core for testing bash scripts

setup() {
  # Create a temporary directory for test fixtures
  export TEST_TEMP_DIR="$(mktemp -d)"
  # Get the directory where the test script is located
  export TEST_DIR="$BATS_TEST_DIRNAME"
  export SCRIPT_PATH="$TEST_DIR/environment-matrix-generator.sh"
}

teardown() {
  # Clean up temporary test files
  rm -rf "$TEST_TEMP_DIR"
}

# Test 1: Script exists and is executable
@test "script exists and has valid bash syntax" {
  [ -f "$SCRIPT_PATH" ]
  bash -n "$SCRIPT_PATH"
}

# Test 2: Basic matrix generation with minimal config
@test "generates basic matrix from minimal config" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": []
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should be valid JSON
  echo "$output" | jq . > /dev/null

  # Should have matrix key
  echo "$output" | jq '.matrix' > /dev/null
}

# Test 3: Matrix includes OS and language version combinations
@test "generates matrix with all OS and language combinations" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest"],
  "language_version": ["1.0", "1.1"],
  "features": []
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should generate 2x2=4 combinations
  count=$(echo "$output" | jq '.matrix.include | length')
  [ "$count" -eq 4 ]
}

# Test 4: Include rules are applied
@test "applies include rules to add custom matrix entries" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": [],
  "include": [
    {"os": "macos-latest", "language_version": "1.0", "custom_flag": "special"}
  ]
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should include the custom entry
  has_macos=$(echo "$output" | jq '.matrix.include[] | select(.os == "macos-latest") | .custom_flag' | grep -q "special" && echo 1 || echo 0)
  [ "$has_macos" -eq 1 ]
}

# Test 5: Exclude rules are applied
@test "applies exclude rules to remove matrix entries" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest"],
  "language_version": ["1.0", "1.1"],
  "features": [],
  "exclude": [
    {"os": "windows-latest", "language_version": "1.1"}
  ]
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # windows-latest + 1.1 should not exist in matrix
  has_excluded=$(echo "$output" | jq '.matrix.include[] | select(.os == "windows-latest" and .language_version == "1.1")' | wc -l)
  [ "$has_excluded" -eq 0 ]
}

# Test 6: Feature flags are included in matrix
@test "includes feature flags in matrix entries" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": ["experimental", "beta"]
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Each entry should have feature flags
  has_features=$(echo "$output" | jq '.matrix.include[0] | has("features")' | grep -q "true" && echo 1 || echo 0)
  [ "$has_features" -eq 1 ]
}

# Test 7: Max parallel limit is set
@test "sets max-parallel limit in strategy" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": [],
  "max_parallel": 3
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should have strategy.max-parallel
  max_parallel=$(echo "$output" | jq '.strategy."max-parallel"')
  [ "$max_parallel" -eq 3 ]
}

# Test 8: Fail-fast configuration is applied
@test "applies fail-fast configuration" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": [],
  "fail_fast": false
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should have strategy.fail-fast set to false
  fail_fast=$(echo "$output" | jq '.strategy."fail-fast"')
  [ "$fail_fast" == "false" ]
}

# Test 9: Matrix size validation passes for reasonable size
@test "validates matrix size and passes for valid size" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest"],
  "language_version": ["1.0", "1.1"],
  "features": [],
  "max_matrix_size": 100
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")
  status=$?

  # Should succeed
  [ $status -eq 0 ]

  # Should generate valid matrix
  echo "$output" | jq . > /dev/null
}

# Test 10: Matrix size validation fails for oversized matrix
@test "validates matrix size and fails for oversized matrix" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
  "language_version": ["1.0", "1.1", "1.2", "1.3"],
  "features": [],
  "max_matrix_size": 5
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json" 2>&1) || status=$?
  status=${status:-0}

  # Should fail
  [ $status -ne 0 ]

  # Should print error message
  echo "$output" | grep -i "matrix size exceeds" > /dev/null
}

# Test 11: Empty configuration handling
@test "handles empty OS or language version gracefully" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": [],
  "language_version": [],
  "features": []
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json" 2>&1) || status=$?
  status=${status:-0}

  # Should fail with meaningful error
  [ $status -ne 0 ]
  echo "$output" | grep -i "os or language" > /dev/null
}

# Test 12: Default strategy values when not specified
@test "uses default strategy values when not specified" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": []
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Should have default strategy
  has_strategy=$(echo "$output" | jq 'has("strategy")' | grep -q "true" && echo 1 || echo 0)
  [ "$has_strategy" -eq 1 ]
}

# Test 13: Output format is GitHub Actions compatible
@test "output format is compatible with GitHub Actions matrix" {
  cat > "$TEST_TEMP_DIR/config.json" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language_version": ["1.0"],
  "features": ["debug"]
}
EOF

  output=$("$SCRIPT_PATH" -c "$TEST_TEMP_DIR/config.json")

  # Must have both 'matrix' and 'strategy' top-level keys
  has_matrix=$(echo "$output" | jq 'has("matrix")' | grep -q "true" && echo 1 || echo 0)
  has_strategy=$(echo "$output" | jq 'has("strategy")' | grep -q "true" && echo 1 || echo 0)

  [ "$has_matrix" -eq 1 ] && [ "$has_strategy" -eq 1 ]
}

# Test 14: Script output passes shellcheck
@test "script passes shellcheck validation" {
  # shellcheck must be available
  command -v shellcheck > /dev/null 2>&1 || skip "shellcheck not installed"

  # Check the script
  shellcheck -S warning "$SCRIPT_PATH"
}
