#!/usr/bin/env bats
# Functional tests for the aggregator, exercised ONLY through the real
# GitHub Actions pipeline via `act` (never by calling aggregate-results.sh
# directly -- see scripts/run-act-harness.sh for why and how).
#
# setup_file runs the harness (and therefore `act push --rm`) exactly
# ONCE for this whole file; every @test below just makes an assertion
# against the resulting act-result.txt content.

setup_file() {
  cd "${BATS_TEST_DIRNAME}/.." || exit 1
  ./scripts/run-act-harness.sh
  echo "$?" > "${BATS_TEST_DIRNAME}/.act_exit_code"
}

setup() {
  cd "${BATS_TEST_DIRNAME}/.." || exit 1
  ACT_OUTPUT="${BATS_TEST_DIRNAME}/../act-result.txt"
}

teardown_file() {
  rm -f "${BATS_TEST_DIRNAME}/.act_exit_code"
}

@test "act-result.txt was produced" {
  [ -f "$ACT_OUTPUT" ]
}

@test "act push exited 0" {
  run cat "${BATS_TEST_DIRNAME}/.act_exit_code"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "the aggregate job succeeded" {
  run grep -c "Job succeeded" "$ACT_OUTPUT"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "no job failure marker is present" {
  run grep -c "Job failed" "$ACT_OUTPUT"
  [ "$status" -eq 1 ]
  [ "$output" -eq 0 ]
}

@test "basic-matrix-aggregation scenario ran" {
  grep -qF "=== SCENARIO: basic-matrix-aggregation ===" "$ACT_OUTPUT"
}

@test "basic-matrix-aggregation: exact overall totals" {
  grep -qF "| Total Tests | 24 |" "$ACT_OUTPUT"
  grep -qF "| Passed | 13 |" "$ACT_OUTPUT"
  grep -qF "| Failed | 7 |" "$ACT_OUTPUT"
  grep -qF "| Skipped | 4 |" "$ACT_OUTPUT"
  grep -qF "| Duration | 3.45s |" "$ACT_OUTPUT"
}

@test "basic-matrix-aggregation: exact per-run breakdown" {
  grep -qF "| run1-ubuntu-py39 | 4 | 1 | 1 | 0.80s |" "$ACT_OUTPUT"
  grep -qF "| run2-ubuntu-py310 | 2 | 3 | 1 | 0.92s |" "$ACT_OUTPUT"
  grep -qF "| run3-macos-py39 | 4 | 1 | 1 | 0.81s |" "$ACT_OUTPUT"
  grep -qF "| run4-windows-py310 | 3 | 2 | 1 | 0.92s |" "$ACT_OUTPUT"
}

@test "basic-matrix-aggregation: exactly 2 flaky tests identified by name" {
  grep -qF "## Flaky Tests (2)" "$ACT_OUTPUT"
  grep -qF "calculator.CalculatorTest::test_divide_by_zero | 3 | 1 |" "$ACT_OUTPUT"
  grep -qF "calculator.CalculatorTest::test_flaky_timing | 2 | 2 |" "$ACT_OUTPUT"
}

@test "basic-matrix-aggregation: consistently-failing test identified with message" {
  grep -qF "## Consistently Failing Tests (1)" "$ACT_OUTPUT"
  grep -qF "calculator.CalculatorTest::test_multiply | 4/4 | AssertionError: expected 6 but got 5 |" "$ACT_OUTPUT"
}

@test "empty-results scenario handled gracefully with zero totals" {
  grep -qF "=== SCENARIO: empty-results ===" "$ACT_OUTPUT"
  grep -qF "| Total Tests | 0 |" "$ACT_OUTPUT"
  grep -qF "No flaky tests detected." "$ACT_OUTPUT"
}

@test "malformed XML is rejected with the exact expected error" {
  grep -qF "=== SCENARIO: malformed-xml-rejected ===" "$ACT_OUTPUT"
  grep -qF "MALFORMED_XML_HANDLED_OK: ERROR: malformed JUnit XML in 'fixtures/malformed.xml': <testcase> missing required 'name' attribute" "$ACT_OUTPUT"
}

@test "invalid JSON is rejected with the exact expected error" {
  grep -qF "=== SCENARIO: invalid-json-rejected ===" "$ACT_OUTPUT"
  grep -qF "INVALID_JSON_HANDLED_OK: ERROR: invalid JSON in file 'fixtures/invalid.json'" "$ACT_OUTPUT"
}

@test "unsupported file extension is rejected with the exact expected error" {
  grep -qF "=== SCENARIO: unsupported-extension-rejected ===" "$ACT_OUTPUT"
  grep -qF "UNSUPPORTED_EXTENSION_HANDLED_OK: ERROR: unsupported result file extension '.txt' for 'fixtures/unsupported.txt' (expected .xml or .json)" "$ACT_OUTPUT"
}
