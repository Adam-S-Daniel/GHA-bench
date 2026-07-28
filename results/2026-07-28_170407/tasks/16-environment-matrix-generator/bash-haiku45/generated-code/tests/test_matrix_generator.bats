#!/usr/bin/env bats

# Test suite for environment matrix generator

setup() {
  export SCRIPT_DIR="$( cd "$( dirname "${BATS_TEST_FILENAME}" )/.." && pwd )"
  export SCRIPT="$SCRIPT_DIR/matrix-generator.sh"
  export TEMP_DIR="$(mktemp -d)"
  cd "$TEMP_DIR"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# TEST 1: Script exists and is executable
@test "matrix generator script exists" {
  [ -f "$SCRIPT" ]
}

# TEST 2: Simple matrix generation - basic OS and version
@test "generates matrix with single OS and single version" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest"],
  "node_version": ["18"]
}
EOF

  result=$("$SCRIPT" config.json)

  echo "$result" | jq . > /dev/null  # verify valid JSON

  # Should contain the cartesian product
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 1 ]
}

# TEST 3: Cartesian product - multiple values per dimension
@test "generates cartesian product with multiple dimensions" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node_version": ["18", "20"]
}
EOF

  result=$("$SCRIPT" config.json)

  # Should be 2 x 2 = 4 combinations
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 4 ]
}

# TEST 4: Include rules override cartesian product
@test "include array overrides cartesian product" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node_version": ["18", "20"],
  "include": [
    {"os": "windows-latest", "node_version": "18"}
  ]
}
EOF

  result=$("$SCRIPT" config.json)

  # When include is specified, it replaces the cartesian product
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 1 ]

  # Verify the included entry
  os=$(echo "$result" | jq -r '.include[0].os')
  [ "$os" = "windows-latest" ]
}

# TEST 5: Exclude rules
@test "exclude array is present in output" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest"],
  "node_version": ["18"],
  "exclude": [
    {"os": "ubuntu-latest", "node_version": "18"}
  ]
}
EOF

  result=$("$SCRIPT" config.json)

  # Verify exclude is in output
  exclude_count=$(echo "$result" | jq '.exclude | length')
  [ "$exclude_count" -eq 1 ]
}

# TEST 6: Fail-fast configuration
@test "fail_fast flag is included in output" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest"],
  "node_version": ["18"],
  "fail_fast": true
}
EOF

  result=$("$SCRIPT" config.json)

  # Check fail-fast in output
  fail_fast=$(echo "$result" | jq '.["fail-fast"]')
  [ "$fail_fast" = "true" ]
}

# TEST 7: Max parallel configuration
@test "max_parallel is included in output when specified" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest"],
  "node_version": ["18"],
  "max_parallel": 5
}
EOF

  result=$("$SCRIPT" config.json)

  # Check max-parallel in output
  max_parallel=$(echo "$result" | jq '.["max-parallel"]')
  [ "$max_parallel" = "5" ]
}

# TEST 8: Matrix size validation - should pass
@test "accepts matrix under max_matrix_size limit" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node_version": ["18"],
  "max_matrix_size": 10
}
EOF

  result=$("$SCRIPT" config.json)

  # Should succeed with 2 entries
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 2 ]
}

# TEST 9: Matrix size validation - should fail
@test "rejects matrix exceeding max_matrix_size limit" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node_version": ["18"],
  "max_matrix_size": 1
}
EOF

  run "$SCRIPT" config.json

  # Should fail with error message
  [ "$status" -ne 0 ]
  [[ "$output" == *"exceeds maximum"* ]]
}

# TEST 10: Invalid JSON handling
@test "rejects invalid JSON config" {
  cat > config.json <<'EOF'
{ invalid json }
EOF

  run "$SCRIPT" config.json

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid JSON"* ]]
}

# TEST 11: Missing config file
@test "handles missing config file" {
  run "$SCRIPT" nonexistent.json

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# TEST 12: Empty dimensions (no arrays)
@test "handles config with empty arrays" {
  cat > config.json <<'EOF'
{
  "os": [],
  "version": []
}
EOF

  result=$("$SCRIPT" config.json)

  # Should handle gracefully
  echo "$result" | jq . > /dev/null
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 0 ]
}

# TEST 13: Three dimensions
@test "generates cartesian product with three dimensions" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu", "macos"],
  "node": ["18", "20"],
  "arch": ["x64", "arm64"]
}
EOF

  result=$("$SCRIPT" config.json)

  # Should be 2 x 2 x 2 = 8 combinations
  include_count=$(echo "$result" | jq '.include | length')
  [ "$include_count" -eq 8 ]
}

# TEST 14: Default fail-fast is false
@test "fail-fast defaults to false when not specified" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu"]
}
EOF

  result=$("$SCRIPT" config.json)

  fail_fast=$(echo "$result" | jq '.["fail-fast"]')
  [ "$fail_fast" = "false" ]
}

# TEST 15: Empty exclude list is present
@test "exclude is empty array when not specified" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu"]
}
EOF

  result=$("$SCRIPT" config.json)

  exclude=$(echo "$result" | jq '.exclude')
  [ "$exclude" = "[]" ]
}

# TEST 16: Script outputs valid JSON structure
@test "output has required top-level keys" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu"],
  "version": ["1"]
}
EOF

  result=$("$SCRIPT" config.json)

  # Check all required keys exist
  include_key=$(echo "$result" | jq 'has("include")')
  exclude_key=$(echo "$result" | jq 'has("exclude")')
  fail_fast_key=$(echo "$result" | jq 'has("fail-fast")')

  [ "$include_key" = "true" ]
  [ "$exclude_key" = "true" ]
  [ "$fail_fast_key" = "true" ]
}

# TEST 17: Include and exclude are arrays
@test "include and exclude are arrays in output" {
  cat > config.json <<'EOF'
{
  "os": ["ubuntu"],
  "include": [{"os": "windows"}]
}
EOF

  result=$("$SCRIPT" config.json)

  include_is_array=$(echo "$result" | jq '.include | type')
  exclude_is_array=$(echo "$result" | jq '.exclude | type')

  [ "$include_is_array" = '"array"' ]
  [ "$exclude_is_array" = '"array"' ]
}
