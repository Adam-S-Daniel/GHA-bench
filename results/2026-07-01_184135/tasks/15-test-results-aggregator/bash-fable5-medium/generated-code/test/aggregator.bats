#!/usr/bin/env bats
# =============================================================================
# TDD test suite for aggregate-test-results.sh
#
# Built red/green: each "Cycle" below was written as a failing test first,
# then the minimum implementation was added to make it pass, then refactored.
#   Cycle 1: argument validation / error handling
#   Cycle 2: JUnit XML parsing and totals
#   Cycle 3: JSON parsing, cross-file aggregation, flaky detection, markdown
# =============================================================================

setup() {
  # Directory of this test file -> project root is one level up
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/aggregate-test-results.sh"
  FIXTURES="$PROJECT_ROOT/fixtures"
  TMPDIR_CASE="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_CASE"
}

# ---------------------------------------------------------------------------
# Cycle 1: error handling (written first, failed until script existed)
# ---------------------------------------------------------------------------

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "fails with usage message when no arguments given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fails with meaningful error for missing directory" {
  run "$SCRIPT" /nonexistent/dir
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"not a directory"* ]]
}

@test "fails with meaningful error when directory has no result files" {
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"no test result files"* ]]
}

@test "fails with meaningful error on malformed JSON" {
  echo '{not json' > "$TMPDIR_CASE/bad.json"
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"invalid JSON"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2: JUnit XML parsing and totals
# ---------------------------------------------------------------------------

@test "parses a single JUnit XML file: pass/fail/skip counts" {
  cp "$FIXTURES/run1.xml" "$TMPDIR_CASE/"
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total | 4 |"* ]]
  [[ "$output" == *"| Passed | 1 |"* ]]
  [[ "$output" == *"| Failed | 2 |"* ]]
  [[ "$output" == *"| Skipped | 1 |"* ]]
}

@test "sums durations from JUnit XML time attributes" {
  cp "$FIXTURES/run1.xml" "$TMPDIR_CASE/"
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -eq 0 ]
  # 0.5 + 1.0 + 0.0 + 2.0 = 3.50s
  [[ "$output" == *"| Duration | 3.50s |"* ]]
}

@test "handles self-closing testcase elements" {
  cat > "$TMPDIR_CASE/self.xml" <<'XML'
<?xml version="1.0"?>
<testsuite name="s" tests="1">
  <testcase classname="suite" name="test_solo" time="0.25"/>
</testsuite>
XML
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total | 1 |"* ]]
  [[ "$output" == *"| Passed | 1 |"* ]]
  [[ "$output" == *"| Duration | 0.25s |"* ]]
}

@test "counts error elements as failures" {
  cat > "$TMPDIR_CASE/err.xml" <<'XML'
<?xml version="1.0"?>
<testsuite name="s" tests="1">
  <testcase classname="suite" name="test_boom" time="0.1">
    <error message="crashed">stack</error>
  </testcase>
</testsuite>
XML
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Failed | 1 |"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 3: JSON parsing, aggregation across files, flaky detection, markdown
# ---------------------------------------------------------------------------

@test "parses a JSON result file" {
  cp "$FIXTURES/run3.json" "$TMPDIR_CASE/"
  run "$SCRIPT" "$TMPDIR_CASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total | 3 |"* ]]
  [[ "$output" == *"| Passed | 3 |"* ]]
  [[ "$output" == *"| Duration | 1.70s |"* ]]
}

@test "aggregates across all fixture files (matrix build simulation)" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total | 11 |"* ]]
  [[ "$output" == *"| Passed | 7 |"* ]]
  [[ "$output" == *"| Failed | 3 |"* ]]
  [[ "$output" == *"| Skipped | 1 |"* ]]
  [[ "$output" == *"| Duration | 8.60s |"* ]]
}

@test "identifies flaky tests (passed in some runs, failed in others)" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Flaky Tests"* ]]
  # test_flaky failed in run1, passed in run2 and run3
  [[ "$output" == *'`suite.test_flaky` — passed 2, failed 1'* ]]
  # test_beta failed in every run: consistently failing, NOT flaky
  [[ "$output" != *'`suite.test_beta` — passed'* ]]
}

@test "lists consistently failing tests separately from flaky ones" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Failed Tests"* ]]
  [[ "$output" == *'`suite.test_beta`'* ]]
}

@test "reports no flaky tests when all runs pass" {
  run "$SCRIPT" "$PROJECT_ROOT/fixtures-allpass"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total | 3 |"* ]]
  [[ "$output" == *"| Passed | 3 |"* ]]
  [[ "$output" == *"| Failed | 0 |"* ]]
  [[ "$output" == *"No flaky tests detected"* ]]
  [[ "$output" == *"| Duration | 1.00s |"* ]]
}

@test "writes markdown summary to output file when given" {
  run "$SCRIPT" "$FIXTURES" "$TMPDIR_CASE/summary.md"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_CASE/summary.md" ]
  grep -q '# Test Results Summary' "$TMPDIR_CASE/summary.md"
  grep -q '| Total | 11 |' "$TMPDIR_CASE/summary.md"
}

@test "markdown output starts with a level-1 heading (GH Actions job summary)" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# Test Results Summary" ]]
}
