#!/usr/bin/env bats
# Red/green TDD suite for matrix-generator.sh.
#
# Each @test targets one behavior. Fixtures live in fixtures/ and are kept
# minimal and purpose-built so expected output can be reasoned about by hand.

setup() {
  # tests/ -> project root
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/matrix-generator.sh"
  FIXTURES="$PROJECT_ROOT/fixtures"
}

# --- Cycle 1: CLI usage / basic error handling -----------------------------

@test "exits 2 with usage message when no config path is given" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "exits 1 with a meaningful error when config file does not exist" {
  run "$SCRIPT" "$FIXTURES/does-not-exist.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"not found"* ]]
}

@test "exits 1 with a meaningful error when config file is not valid JSON" {
  run "$SCRIPT" "$FIXTURES/bad-json.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"invalid JSON"* ]]
}

# --- Cycle 2: axis validation -----------------------------------------------

@test "exits 1 when no axes (os/versions/flags) are defined" {
  run "$SCRIPT" "$FIXTURES/no-axes.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"at least one axis"* ]]
}

@test "exits 1 when an axis array is empty" {
  run "$SCRIPT" "$FIXTURES/empty-axis-array.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"'node'"* ]]
  [[ "$output" == *"non-empty"* ]]
}

@test "exits 1 when versions/flags define a duplicate axis key" {
  run "$SCRIPT" "$FIXTURES/duplicate-axis-key.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"duplicate axis"* ]]
  [[ "$output" == *"'node'"* ]]
}

# --- Cycle 3: basic cartesian product ---------------------------------------

@test "generates the cartesian product of os and versions with fail-fast default true" {
  run "$SCRIPT" "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  expected='{"matrix":{"include":[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"20"},{"os":"windows-latest","node":"18"},{"os":"windows-latest","node":"20"}]},"fail-fast":true}'
  actual=$(echo "$output" | jq -c -S '.matrix.include |= sort_by(.os, .node)')
  expected_sorted=$(echo "$expected" | jq -c -S '.matrix.include |= sort_by(.os, .node)')
  [ "$actual" = "$expected_sorted" ]
}

@test "output is valid JSON on stdout" {
  run "$SCRIPT" "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

# --- Cycle 4: exclude rules --------------------------------------------------

@test "exclude rules remove matching combinations from the matrix" {
  run "$SCRIPT" "$FIXTURES/with-exclude.json"
  [ "$status" -eq 0 ]
  size=$(echo "$output" | jq '.matrix.include | length')
  [ "$size" -eq 7 ]
  # neither excluded combo should be present
  present=$(echo "$output" | jq '[.matrix.include[] | select(.os == "windows-latest" and .node == "18")] | length')
  [ "$present" -eq 0 ]
  present=$(echo "$output" | jq '[.matrix.include[] | select(.os == "macos-latest" and .node == "22")] | length')
  [ "$present" -eq 0 ]
}

@test "exits 1 when an exclude rule references an unknown axis" {
  run "$SCRIPT" "$FIXTURES/unknown-exclude-key.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"unknown axis"* ]]
  [[ "$output" == *"'python'"* ]]
}

@test "exits 1 when exclude rules remove every combination" {
  run "$SCRIPT" "$FIXTURES/empty-result.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"empty"* ]]
}

# --- Cycle 5: include rules (matches documented GitHub Actions semantics) --

@test "include rules match the documented GitHub Actions fruit/animal/color example" {
  run "$SCRIPT" "$FIXTURES/gh-docs-include.json"
  [ "$status" -eq 0 ]
  actual=$(echo "$output" | jq -c -S '.matrix.include | sort_by(.fruit, .animal, .color // "")')
  expected='[{"fruit":"apple","animal":"cat","color":"pink","shape":"circle"},{"fruit":"apple","animal":"dog","color":"green","shape":"circle"},{"fruit":"pear","animal":"cat","color":"pink"},{"fruit":"pear","animal":"dog","color":"green"},{"fruit":"banana"}]'
  expected_sorted=$(echo "$expected" | jq -c -S 'sort_by(.fruit, .animal, .color // "")')
  [ "$actual" = "$expected_sorted" ]
}

# --- Cycle 6: max-parallel / fail-fast passthrough --------------------------

@test "passes through max_parallel and fail_fast from config" {
  run "$SCRIPT" "$FIXTURES/with-max-parallel-failfast.json"
  [ "$status" -eq 0 ]
  mp=$(echo "$output" | jq '.["max-parallel"]')
  ff=$(echo "$output" | jq '.["fail-fast"]')
  [ "$mp" -eq 2 ]
  [ "$ff" = "false" ]
}

@test "exits 1 when max_parallel is not a positive integer" {
  run "$SCRIPT" "$FIXTURES/bad-max-parallel.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"max_parallel"* ]]
}

@test "exits 1 when fail_fast is not a boolean" {
  run "$SCRIPT" "$FIXTURES/bad-fail-fast.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"fail_fast"* ]]
}

# --- Cycle 7: max-size validation -------------------------------------------

@test "exits 1 when the resolved matrix exceeds max_size" {
  run "$SCRIPT" "$FIXTURES/oversized.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error:"* ]]
  [[ "$output" == *"exceeds maximum allowed size"* ]]
  [[ "$output" == *"20"* ]]
  [[ "$output" == *"10"* ]]
}

# --- Cycle 8: feature flags (booleans) and output shape edge cases --------

@test "boolean feature flags are preserved as real JSON booleans in output" {
  run "$SCRIPT" "$FIXTURES/with-flags.json"
  [ "$status" -eq 0 ]
  size=$(echo "$output" | jq '.matrix.include | length')
  [ "$size" -eq 4 ]
  bool_count=$(echo "$output" | jq '[.matrix.include[] | select(.experimental == true or .experimental == false)] | length')
  [ "$bool_count" -eq 4 ]
  type_count=$(echo "$output" | jq '[.matrix.include[] | select(.experimental | type == "boolean")] | length')
  [ "$type_count" -eq 4 ]
}

@test "max-parallel key is omitted from output when not set in config" {
  run "$SCRIPT" "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  has_key=$(echo "$output" | jq 'has("max-parallel")')
  [ "$has_key" = "false" ]
}

@test "exclude and include rules compose correctly (exclude first, include layered on top)" {
  run "$SCRIPT" "$FIXTURES/ci-example-with-rules.json"
  [ "$status" -eq 0 ]
  actual=$(echo "$output" | jq -c -S '.matrix.include | sort_by(.node)')
  expected='[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"22","codename":"jammy-plus"}]'
  expected_sorted=$(echo "$expected" | jq -c -S 'sort_by(.node)')
  [ "$actual" = "$expected_sorted" ]
}
