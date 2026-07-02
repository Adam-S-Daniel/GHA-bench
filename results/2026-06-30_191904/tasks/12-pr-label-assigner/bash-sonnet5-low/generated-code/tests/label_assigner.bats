#!/usr/bin/env bats
# Tests for scripts/label_assigner.sh
# Uses bats-core. Run with: bats tests/label_assigner.bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/label_assigner.sh"
  RULES="$BATS_TEST_DIRNAME/../rules.conf"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures"
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "fails gracefully when rules file is missing" {
  run "$SCRIPT" --rules /nonexistent/rules.conf --files "$FIXTURES/simple_docs.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rules file not found"* ]]
}

@test "fails gracefully when files list is missing" {
  run "$SCRIPT" --rules "$RULES" --files /nonexistent/files.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"files list not found"* ]]
}

@test "assigns documentation label for docs/** files" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/simple_docs.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"documentation"* ]]
}

@test "assigns api label for src/api/** files" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/api_change.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
}

@test "assigns tests label for *.test.* glob files" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/test_change.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests"* ]]
}

@test "assigns multiple labels for multiple distinct files" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/mixed_change.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"documentation"* ]]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"tests"* ]]
}

@test "a single file can receive multiple labels" {
  # src/api/foo.test.js matches both api and tests rules
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/api_test_change.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"tests"* ]]
}

@test "labels are deduplicated when multiple files match same label" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/multiple_docs.txt"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -o "documentation" | wc -l)
  [ "$count" -eq 1 ]
}

@test "output is ordered by rule priority (lowest number first)" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/mixed_change.txt"
  [ "$status" -eq 0 ]
  # documentation (priority 10) should appear before tests (priority 30)
  doc_line=$(echo "$output" | grep -n "^documentation$" | cut -d: -f1)
  tests_line=$(echo "$output" | grep -n "^tests$" | cut -d: -f1)
  [ "$doc_line" -lt "$tests_line" ]
}

@test "unmatched files produce no labels" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/no_match.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "supports json output format" {
  run "$SCRIPT" --rules "$RULES" --files "$FIXTURES/simple_docs.txt" --format json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"documentation"'* ]]
}
