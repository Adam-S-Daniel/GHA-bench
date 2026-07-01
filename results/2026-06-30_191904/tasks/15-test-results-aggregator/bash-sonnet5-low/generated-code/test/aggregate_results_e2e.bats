#!/usr/bin/env bats
# TDD: end-to-end test of bin/aggregate-results.sh against the matrix fixtures,
# which contain a deliberately flaky test (test_network_timeout: pass, pass, fail).

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MAIN="$ROOT_DIR/bin/aggregate-results.sh"
  FIXTURES="$ROOT_DIR/fixtures"
}

@test "main script auto-detects format by extension and aggregates matrix fixtures" {
  run "$MAIN" "$FIXTURES/matrix/ubuntu.xml" "$FIXTURES/matrix/macos.xml" "$FIXTURES/matrix/windows.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Test Results Summary"* ]]
  [[ "$output" == *"| Passed | 5 |"* ]]
  [[ "$output" == *"| Failed | 1 |"* ]]
  [[ "$output" == *"| Skipped | 0 |"* ]]
  [[ "$output" == *"test_network_timeout"* ]]
}

@test "main script writes to GITHUB_STEP_SUMMARY when set" {
  local summary_file="$BATS_TEST_TMPDIR/summary.md"
  GITHUB_STEP_SUMMARY="$summary_file" run "$MAIN" "$FIXTURES/junit_sample.xml"
  [ "$status" -eq 0 ]
  [ -f "$summary_file" ]
  grep -q "# Test Results Summary" "$summary_file"
}

@test "main script errors out with meaningful message when no args given" {
  run "$MAIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"no input files"* ]]
}

@test "main script errors out when a given file does not exist" {
  run "$MAIN" "$FIXTURES/nope.xml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "main script rejects unrecognized file extensions" {
  run "$MAIN" "$FIXTURES/json_sample.json.bak"
  [ "$status" -ne 0 ]
}
