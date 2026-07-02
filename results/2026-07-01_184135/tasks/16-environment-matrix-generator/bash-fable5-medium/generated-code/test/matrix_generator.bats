#!/usr/bin/env bats
# Tests for matrix_generator.sh — TDD suite.
# Each test feeds a fixture config through the script and asserts on the
# exact JSON produced (normalized with `jq -c -S` for stable comparison).

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/matrix_generator.sh"
  FIXTURES="$PROJECT_ROOT/test/fixtures"
}

# Helper: run the script and normalize its JSON output for exact comparison.
run_normalized() {
  run bash -c "'$SCRIPT' '$1' | jq -c -S ."
}

@test "basic config expands cartesian product of os x versions" {
  run_normalized "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  expected='{"fail-fast":true,"matrix":{"include":[{"os":"ubuntu-latest","version":"18"},{"os":"ubuntu-latest","version":"20"},{"os":"macos-latest","version":"18"},{"os":"macos-latest","version":"20"}]}}'
  [ "$output" = "$(echo "$expected" | jq -c -S .)" ]
}

@test "full config applies features, exclude, include, fail-fast and max-parallel" {
  run_normalized "$FIXTURES/full.json"
  [ "$status" -eq 0 ]
  # 2 os x 2 versions x 2 tls = 8, minus 2 excluded (windows+tls=true),
  # include #1 matches nothing -> appended, include #2 augments the two
  # ubuntu/3.12 combos with coverage:true.
  expected='{"fail-fast":false,"max-parallel":3,"matrix":{"include":[
    {"os":"ubuntu-latest","version":"3.11","tls":true},
    {"os":"ubuntu-latest","version":"3.11","tls":false},
    {"os":"ubuntu-latest","version":"3.12","tls":true,"coverage":true},
    {"os":"ubuntu-latest","version":"3.12","tls":false,"coverage":true},
    {"os":"windows-latest","version":"3.11","tls":false},
    {"os":"windows-latest","version":"3.12","tls":false},
    {"os":"ubuntu-latest","version":"3.13","tls":true,"experimental":true}
  ]}}'
  [ "$output" = "$(echo "$expected" | jq -c -S .)" ]
}

@test "matrix exceeding configured max-size fails with a clear error" {
  run "$SCRIPT" "$FIXTURES/too_big.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 4 exceeds maximum allowed size 3"* ]]
}

@test "matrix exceeding default max-size (256) fails" {
  cfg="$BATS_TEST_TMPDIR/big.json"
  jq -n '{os: ["ubuntu-latest"], versions: [range(300) | tostring]}' > "$cfg"
  run "$SCRIPT" "$cfg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 300 exceeds maximum allowed size 256"* ]]
}

@test "invalid JSON config fails with a clear error" {
  run "$SCRIPT" "$FIXTURES/invalid.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "missing config file fails with a clear error" {
  run "$SCRIPT" "$FIXTURES/does_not_exist.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "config with no dimensions fails with a clear error" {
  run "$SCRIPT" "$FIXTURES/empty.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"at least one dimension"* ]]
}

@test "missing argument prints usage" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
