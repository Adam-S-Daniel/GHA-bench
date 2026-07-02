#!/usr/bin/env bats
# TDD test suite for the PR Label Assigner script.
# Run with: bats tests/pr_label_assigner.bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/pr-label-assigner.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures"
}

# --- RED: first failing test -------------------------------------------
# The script does not exist yet. This should fail until we create it.
@test "script file exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "passes shellcheck" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "passes bash -n syntax check" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "errors with meaningful message when no arguments given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--files"* ]]
}

@test "errors when --files argument is missing" {
  run "$SCRIPT" --rules "$FIXTURES/rules.conf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--files"* ]]
}

@test "errors when --rules argument is missing" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_basic.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--rules"* ]]
}

@test "errors with meaningful message when files list path does not exist" {
  run "$SCRIPT" --files "$FIXTURES/does_not_exist.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* || "$output" == *"No such file"* ]]
}

@test "errors with meaningful message when rules file path does not exist" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_basic.txt" --rules "$FIXTURES/does_not_exist.conf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* || "$output" == *"No such file"* ]]
}

# --- Core label-assignment behaviour ------------------------------------

@test "basic mapping: docs/**, src/api/**, *.test.*, *.md all resolve correctly" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_basic.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"documentation"* ]]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"tests"* ]]
  [[ "$output" == *"source"* ]]
}

@test "empty changed-files list produces no labels and exits 0" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_empty.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "files matching no rule produce no labels" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_nomatch.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "conflicting rules in the same group resolve by priority" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_conflict.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -eq 0 ]
  # src/** (priority 60, group area) beats src/vendor/** (priority 55, group area)
  [[ "$output" == *"source"* ]]
  # vendor/** (no group) still applies independently for vendor/lib/thing.js
  [[ "$output" == *"vendor"* ]]
  # the lower-priority "vendor" label must NOT have been applied to the
  # src/vendor/utils.js file's conflict -- only one "vendor" line should
  # come from vendor/lib/thing.js. Verify no duplicate labels are output.
  labels_count=$(echo "$output" | grep -c '^vendor$')
  [ "$labels_count" -eq 1 ]
}

@test "output has no duplicate labels" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_basic.txt" --rules "$FIXTURES/rules.conf"
  [ "$status" -eq 0 ]
  sorted_unique_count=$(echo "$output" | sort -u | wc -l)
  total_count=$(echo "$output" | wc -l)
  [ "$sorted_unique_count" -eq "$total_count" ]
}

@test "json format outputs a valid JSON array of labels" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_basic.txt" --rules "$FIXTURES/rules.conf" --format json
  [ "$status" -eq 0 ]
  [[ "$output" == \[*\] ]]
  [[ "$output" == *"\"documentation\""* ]]
  [[ "$output" == *"\"api\""* ]]
}

@test "json format outputs empty array for no matches" {
  run "$SCRIPT" --files "$FIXTURES/changed_files_nomatch.txt" --rules "$FIXTURES/rules.conf" --format json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}
