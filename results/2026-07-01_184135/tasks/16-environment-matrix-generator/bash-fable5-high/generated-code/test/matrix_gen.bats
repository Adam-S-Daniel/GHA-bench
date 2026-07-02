# Unit tests for matrix-gen.sh — the environment matrix generator.
#
# TDD approach: each @test block was written BEFORE the implementation code
# that satisfies it (red/green/refactor). Tests are grouped by the cycle in
# which they were introduced.

setup() {
  # Absolute path to the script under test and its fixtures.
  SCRIPT="$BATS_TEST_DIRNAME/../matrix-gen.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# --- Cycle 1: CLI basics and config-file error handling -----------------

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "fails with meaningful error when config file is missing" {
  run "$SCRIPT" --config /nonexistent/config.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "fails with usage message on unknown option" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- Cycle 2: basic matrix generation ------------------------------------

@test "generates valid JSON for a basic config" {
  run "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
}

@test "matrix contains the configured os, language-version and feature-flag axes" {
  run "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.matrix.os')" = '["ubuntu-latest","macos-latest"]' ]
  [ "$(echo "$output" | jq -c '.matrix["language-version"]')" = '["3.11","3.12"]' ]
  [ "$(echo "$output" | jq -c '.matrix["feature-flag"]')" = '["standard"]' ]
}

@test "fail-fast defaults to true (GitHub Actions default)" {
  run "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '."fail-fast"')" = "true" ]
}

@test "max-parallel key is omitted when not configured" {
  run "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'has("max-parallel")')" = "false" ]
}

@test "include/exclude keys are omitted when not configured" {
  run "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.matrix | has("include")')" = "false" ]
  [ "$(echo "$output" | jq '.matrix | has("exclude")')" = "false" ]
}

@test "reads config from stdin when --config is not given" {
  run bash -c "'$SCRIPT' < '$FIXTURES/basic.json'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.matrix.os')" = '["ubuntu-latest","macos-latest"]' ]
}

@test "--compact emits single-line JSON" {
  run "$SCRIPT" --config "$FIXTURES/basic.json" --compact
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | jq -e . > /dev/null
}

# --- Cycle 3: include/exclude rules, fail-fast and max-parallel ----------

@test "honours fail-fast=false from the config" {
  run "$SCRIPT" --config "$FIXTURES/full.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '."fail-fast"')" = "false" ]
}

@test "emits max-parallel when configured" {
  run "$SCRIPT" --config "$FIXTURES/full.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '."max-parallel"')" = "4" ]
}

@test "passes include rules through into the matrix" {
  run "$SCRIPT" --config "$FIXTURES/full.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.matrix.include')" = \
    '[{"os":"ubuntu-latest","language-version":"3.13","feature-flag":"standard"}]' ]
}

@test "passes exclude rules through into the matrix" {
  run "$SCRIPT" --config "$FIXTURES/full.json"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.matrix.exclude')" = \
    '[{"os":"macos-latest","feature-flag":"experimental"}]' ]
}

# --- Cycle 4: configuration validation ------------------------------------

# Helper: run the script against an inline JSON config string.
run_with_config() {
  run bash -c "echo '$1' | '$SCRIPT'"
}

@test "fails with meaningful error on invalid JSON" {
  run_with_config 'this is { not json'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "fails when a required axis is missing" {
  run_with_config '{"language-versions":["3.12"],"feature-flags":["standard"]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'os' must be a non-empty array of strings"* ]]
}

@test "fails when an axis is empty" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":[],"feature-flags":["standard"]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'language-versions' must be a non-empty array of strings"* ]]
}

@test "fails when an axis is not an array of strings" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":["3.12"],"feature-flags":"standard"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'feature-flags' must be a non-empty array of strings"* ]]
}

@test "fails when fail-fast is not a boolean" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":["3.12"],"feature-flags":["standard"],"fail-fast":"yes"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'fail-fast' must be a boolean"* ]]
}

@test "fails when max-parallel is not a positive integer" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":["3.12"],"feature-flags":["standard"],"max-parallel":0}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'max-parallel' must be a positive integer"* ]]
}

@test "fails when include is not an array of objects" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":["3.12"],"feature-flags":["standard"],"include":["oops"]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'include' must be an array of objects"* ]]
}

@test "fails when exclude is not an array of objects" {
  run_with_config '{"os":["ubuntu-latest"],"language-versions":["3.12"],"feature-flags":["standard"],"exclude":[42]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"'exclude' must be an array of objects"* ]]
}

# --- Cycle 5: matrix size validation --------------------------------------
#
# Effective size = cartesian product of the three axes
#                  - combinations removed by exclude rules (partial match)
#                  + include entries that introduce brand-new combinations.
# full.json: 2*2*2 = 8, exclude removes 2 (macos-latest x experimental
# across both language versions), include adds 1 new combo (3.13) => 7.

@test "accepts a matrix exactly at the size limit" {
  run "$SCRIPT" --config "$FIXTURES/full.json" --max-size 7
  [ "$status" -eq 0 ]
}

@test "rejects a matrix that exceeds --max-size, reporting the exact size" {
  run "$SCRIPT" --config "$FIXTURES/full.json" --max-size 6
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 7 exceeds maximum allowed size 6"* ]]
}

@test "rejects a matrix that exceeds the default GitHub Actions limit of 256" {
  run "$SCRIPT" --config "$FIXTURES/too-large.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 294 exceeds maximum allowed size 256"* ]]
}

@test "honours max-size from the config file" {
  run bash -c "jq '. + {\"max-size\": 6}' '$FIXTURES/full.json' | '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 7 exceeds maximum allowed size 6"* ]]
}

@test "--max-size on the command line overrides max-size in the config" {
  run bash -c "jq '. + {\"max-size\": 6}' '$FIXTURES/full.json' | '$SCRIPT' --max-size 10"
  [ "$status" -eq 0 ]
}

@test "rejects a non-numeric --max-size" {
  run "$SCRIPT" --config "$FIXTURES/basic.json" --max-size banana
  [ "$status" -eq 1 ]
  [[ "$output" == *"max-size must be a positive integer"* ]]
}

@test "exclude rules use partial matching when counting the matrix size" {
  # Excluding all of macos-latest (partial rule: only "os" given) removes
  # 4 of the 8 combinations in full.json; the include adds 1 => size 5.
  run bash -c "jq '.exclude = [{\"os\": \"macos-latest\"}]' '$FIXTURES/full.json' | '$SCRIPT' --max-size 4"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matrix size 5 exceeds maximum allowed size 4"* ]]
}

@test "include entries matching an existing combination do not add to the size" {
  # This include duplicates an existing combo, so size stays at 2*2*2-2 = 6.
  run bash -c "jq '.include = [{\"os\": \"ubuntu-latest\", \"language-version\": \"3.11\", \"feature-flag\": \"standard\"}]' \
    '$FIXTURES/full.json' | '$SCRIPT' --max-size 6"
  [ "$status" -eq 0 ]
}

@test "fails gracefully when jq is unavailable (mocked minimal PATH)" {
  # Mock a machine without jq: build a PATH that contains only the tools
  # the script needs to reach its dependency check (env, bash, cat).
  local stub="$BATS_TEST_TMPDIR/nobin"
  mkdir -p "$stub"
  ln -s "$(command -v bash)" "$stub/bash"
  ln -s "$(command -v cat)" "$stub/cat"
  ln -s "$(command -v env)" "$stub/env"
  run env PATH="$stub" "$SCRIPT" --config "$FIXTURES/basic.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"required dependency 'jq' is not installed"* ]]
}
