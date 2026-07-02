#!/usr/bin/env bats
# Unit tests for aggregate-test-results.sh
#
# TDD approach: each test below was written BEFORE the code that makes it
# pass (red/green/refactor). Tests exercise the script both as a CLI and
# by sourcing it to unit-test individual functions.

setup() {
  # Resolve repo root relative to this test file so bats can run from anywhere.
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/aggregate-test-results.sh"
  FIXTURES="$REPO_ROOT/fixtures"
  # Scratch dir for per-test artifacts (auto-cleaned by teardown).
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# --- Cycle 1: CLI contract -------------------------------------------------

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "fails with usage message when no arguments given" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fails with a meaningful error for a nonexistent results directory" {
  run "$SCRIPT" "$TMPDIR_TEST/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a directory"* ]]
}

# --- Cycle 2: JUnit XML parsing --------------------------------------------
# parse_junit_xml emits one normalized TSV record per testcase:
#   run_id <TAB> test_id <TAB> status <TAB> duration
# Durations are normalized to 3 decimal places (awk printf) so output is
# deterministic regardless of the jq/awk versions in the environment.

@test "parse_junit_xml: normalizes passed, failed and skipped testcases" {
  source "$SCRIPT"
  run parse_junit_xml "$FIXTURES/matrix-flaky/run1-junit.xml"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'run1-junit.xml\tmath.test_add\tpassed\t0.500')" ]
  [ "${lines[1]}" = "$(printf 'run1-junit.xml\tmath.test_div\tfailed\t0.300')" ]
  [ "${lines[2]}" = "$(printf 'run1-junit.xml\tmath.test_skip\tskipped\t0.000')" ]
  [ "${lines[3]}" = "$(printf 'run1-junit.xml\tapi.test_login\tpassed\t1.200')" ]
  [ "${#lines[@]}" -eq 4 ]
}

# --- Cycle 3: JSON parsing --------------------------------------------------
# JSON schema: {"suite": "...", "tests": [{"name","status","duration"}]}
# where "name" is the fully-qualified test id.

@test "parse_json_results: normalizes JSON test records" {
  source "$SCRIPT"
  run parse_json_results "$FIXTURES/matrix-flaky/run3.json"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'run3.json\tui.test_render\tpassed\t2.000')" ]
  [ "${lines[1]}" = "$(printf 'run3.json\tui.test_click\tfailed\t0.100')" ]
  [ "${lines[2]}" = "$(printf 'run3.json\tapi.test_login\tpassed\t1.000')" ]
  [ "${lines[3]}" = "$(printf 'run3.json\tui.test_modal\tskipped\t0.000')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "parse_json_results: rejects malformed JSON with a clear error" {
  source "$SCRIPT"
  echo '{ this is broken json' > "$TMPDIR_TEST/broken.json"
  run parse_json_results "$TMPDIR_TEST/broken.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.json"* ]]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "parse_json_results: rejects JSON without a tests array" {
  source "$SCRIPT"
  echo '{"suite": "x"}' > "$TMPDIR_TEST/notests.json"
  run parse_json_results "$TMPDIR_TEST/notests.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing a 'tests' array"* ]]
}

# --- Cycle 4: aggregation and flaky detection -------------------------------
# collect_records DIR   -> concatenated normalized records from every *.xml
#                          and *.json file in DIR (sorted by file name).
# compute_totals        -> stdin records to one TSV line:
#                          total passed failed skipped duration(%.2f)
# find_flaky_tests      -> stdin records to TSV lines "test_id passed failed"
#                          for tests that BOTH passed and failed across runs.

@test "collect_records: gathers records from all xml and json files" {
  source "$SCRIPT"
  run collect_records "$FIXTURES/matrix-flaky"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 12 ]
}

@test "collect_records: errors when directory contains no result files" {
  source "$SCRIPT"
  run collect_records "$TMPDIR_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no test result files"* ]]
}

@test "compute_totals: counts statuses and sums durations across the matrix" {
  # 12 tests: 7 passed, 2 failed, 3 skipped; 2.0 + 1.85 + 3.1 = 6.95s
  run bash -c "source '$SCRIPT'; collect_records '$FIXTURES/matrix-flaky' | compute_totals"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '12\t7\t2\t3\t6.95')" ]
}

@test "find_flaky_tests: flags tests that both passed and failed across runs" {
  # math.test_div fails in run1 but passes in run2 -> flaky.
  # ui.test_click always fails and api.test_login always passes -> not flaky.
  run bash -c "source '$SCRIPT'; collect_records '$FIXTURES/matrix-flaky' | find_flaky_tests"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'math.test_div\t1\t1')" ]
}

@test "find_flaky_tests: reports nothing when no test is flaky" {
  run bash -c "source '$SCRIPT'; collect_records '$FIXTURES/all-pass' | find_flaky_tests"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse_junit_xml: rejects a file with no JUnit content" {
  source "$SCRIPT"
  echo "this is not xml at all" > "$TMPDIR_TEST/garbage.xml"
  run parse_junit_xml "$TMPDIR_TEST/garbage.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"garbage.xml"* ]]
  [[ "$output" == *"not a JUnit XML"* ]]
}

# --- Cycle 5: markdown summary (end-to-end CLI) ------------------------------

@test "end-to-end: markdown summary for a matrix with flaky and failed tests" {
  run "$SCRIPT" "$FIXTURES/matrix-flaky"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# 🧪 Test Results Summary"* ]]
  [[ "$output" == *"| Total tests | 12 |"* ]]
  [[ "$output" == *"| ✅ Passed | 7 |"* ]]
  [[ "$output" == *"| ❌ Failed | 2 |"* ]]
  [[ "$output" == *"| ⏭️ Skipped | 3 |"* ]]
  [[ "$output" == *"| ⏱️ Duration | 6.95s |"* ]]
  # Flaky table: math.test_div passed once and failed once across the matrix.
  [[ "$output" == *"| \`math.test_div\` | 1 | 1 |"* ]]
  # Failed-tests table lists which run each failure came from.
  [[ "$output" == *"| \`math.test_div\` | run1-junit.xml |"* ]]
  [[ "$output" == *"| \`ui.test_click\` | run3.json |"* ]]
}

@test "end-to-end: all-green matrix reports no flaky and no failed tests" {
  run "$SCRIPT" "$FIXTURES/all-pass"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Total tests | 4 |"* ]]
  [[ "$output" == *"| ✅ Passed | 4 |"* ]]
  [[ "$output" == *"| ❌ Failed | 0 |"* ]]
  [[ "$output" == *"| ⏱️ Duration | 1.00s |"* ]]
  [[ "$output" == *"No flaky tests detected"* ]]
  [[ "$output" == *"No failed tests"* ]]
}

@test "end-to-end: -o writes the summary to a file instead of stdout" {
  run "$SCRIPT" -o "$TMPDIR_TEST/summary.md" "$FIXTURES/all-pass"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_TEST/summary.md" ]
  grep -qF "| Total tests | 4 |" "$TMPDIR_TEST/summary.md"
  grep -qF "No flaky tests detected" "$TMPDIR_TEST/summary.md"
}

@test "end-to-end: a malformed file anywhere in the directory fails loudly" {
  cp "$FIXTURES/all-pass/run1-junit.xml" "$TMPDIR_TEST/"
  echo '{ nope' > "$TMPDIR_TEST/broken.json"
  run "$SCRIPT" "$TMPDIR_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.json"* ]]
  [[ "$output" == *"invalid JSON"* ]]
}
