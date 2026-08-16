#!/usr/bin/env bats
# Test suite for environment matrix generator using bats-core
# TDD approach: failing tests first, minimal implementation next

setup_file() {
  # Create test fixtures directory
  export TEST_FIXTURES="/tmp/matrix-gen-fixtures-$$"
  mkdir -p "$TEST_FIXTURES"

  # Simple OS matrix configuration
  cat > "$TEST_FIXTURES/simple.json" <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["18", "20"],
  "include": [],
  "exclude": []
}
EOF

  # Configuration with exclude rules
  cat > "$TEST_FIXTURES/with-exclude.json" <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["18", "20"],
  "include": [],
  "exclude": [
    {"os": "macos-latest", "node": "18"}
  ]
}
EOF

  # Configuration with include rules
  cat > "$TEST_FIXTURES/with-include.json" <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["18", "20"],
  "include": [
    {"os": "windows-latest", "node": "20"}
  ],
  "exclude": []
}
EOF

  # Configuration with max-parallel and fail-fast
  cat > "$TEST_FIXTURES/with-strategy.json" <<'EOF'
{
  "os": ["ubuntu-latest"],
  "node": ["18"],
  "include": [],
  "exclude": [],
  "max-parallel": 2,
  "fail-fast": false
}
EOF

  # Configuration exceeding max matrix size
  cat > "$TEST_FIXTURES/oversized.json" <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest", "windows-latest", "ubuntu-20.04"],
  "node": ["14", "16", "18", "20"],
  "python": ["3.8", "3.9", "3.10", "3.11"],
  "include": [],
  "exclude": []
}
EOF
}

# Test 1: Script exists and is executable
@test "matrix-generator.sh exists and is executable" {
  [ -x ./matrix-generator.sh ]
}

# Test 2: Script outputs valid JSON
@test "generates valid JSON for simple matrix" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/simple.json")
  echo "$output" | jq . > /dev/null  # jq validates JSON
}

# Test 3: Generated matrix contains all combinations
@test "simple matrix has all combinations (2 OS × 2 Node = 4)" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/simple.json")
  count=$(echo "$output" | jq '.include | length')
  [ "$count" -eq 4 ]
}

# Test 4: Generated matrix has correct structure with include key
@test "matrix has 'include' and 'strategy' keys" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/simple.json")
  has_include=$(echo "$output" | jq 'has("include")')
  has_strategy=$(echo "$output" | jq 'has("strategy")')
  [ "$has_include" = "true" ]
  [ "$has_strategy" = "true" ]
}

# Test 5: Exclude rules are applied
@test "exclude rules remove matching combinations" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/with-exclude.json")
  count=$(echo "$output" | jq '.include | length')
  # 2 OS × 2 Node - 1 excluded = 3
  [ "$count" -eq 3 ]
}

# Test 6: Excluded combinations don't appear
@test "excluded macos-18 combination is not in matrix" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/with-exclude.json")
  found=$(echo "$output" | jq '.include[] | select(.os=="macos-latest" and .node=="18") | length')
  [ -z "$found" ] || [ "$found" -eq 0 ]
}

# Test 7: Include rules add new combinations
@test "include rules add new combinations" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/with-include.json")
  count=$(echo "$output" | jq '.include | length')
  # 2 OS × 2 Node + 1 included = 5
  [ "$count" -eq 5 ]
}

# Test 8: Include combinations appear in matrix
@test "included windows-20 combination is in matrix" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/with-include.json")
  found=$(echo "$output" | jq '.include[] | select(.os=="windows-latest" and .node=="20")')
  [ -n "$found" ]
}

# Test 9: Strategy options are preserved
@test "strategy options (max-parallel, fail-fast) are in output" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/with-strategy.json")
  max_parallel=$(echo "$output" | jq '.strategy."max-parallel"')
  fail_fast=$(echo "$output" | jq '.strategy."fail-fast"')
  [ "$max_parallel" -eq 2 ]
  [ "$fail_fast" = "false" ]
}

# Test 10: Matrix size validation
@test "oversized matrix exceeds max size limit and exits with error" {
  run ./matrix-generator.sh "$TEST_FIXTURES/oversized.json" --max-size 50
  [ "$status" -ne 0 ]
}

# Test 11: Matrix size validation passes when within limit
@test "matrix within size limit succeeds" {
  run ./matrix-generator.sh "$TEST_FIXTURES/simple.json" --max-size 10
  [ "$status" -eq 0 ]
}

# Test 12: Error handling for missing input file
@test "script exits with error for missing input file" {
  run ./matrix-generator.sh "/nonexistent/file.json"
  [ "$status" -ne 0 ]
}

# Test 13: Error handling for invalid JSON
@test "script exits with error for invalid JSON" {
  echo "{ invalid json" > "$TEST_FIXTURES/bad.json"
  run ./matrix-generator.sh "$TEST_FIXTURES/bad.json"
  [ "$status" -ne 0 ]
}

# Test 14: Default max-size limit is respected
@test "default max-size limit is 256" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/simple.json")
  # Should succeed with default limit
  [ $? -eq 0 ]
}

# Test 15: Matrix entries have all required keys from input
@test "matrix entries contain all input variables" {
  output=$(./matrix-generator.sh "$TEST_FIXTURES/simple.json")
  first_entry=$(echo "$output" | jq '.include[0]')
  has_os=$(echo "$first_entry" | jq 'has("os")')
  has_node=$(echo "$first_entry" | jq 'has("node")')
  [ "$has_os" = "true" ]
  [ "$has_node" = "true" ]
}
