#!/usr/bin/env bats
#
# Unit / behaviour tests for aggregate.sh (the test-results aggregator).
#
# These tests drive the script logic directly. The end-to-end workflow tests
# that run everything through GitHub Actions live in test_act.bats.

setup() {
  # Resolve repo root (directory containing this test file).
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  SCRIPT="$REPO_ROOT/aggregate.sh"
  FIXTURES="$REPO_ROOT/fixtures"
  # Source the script so we can call its functions directly. The script only
  # runs main() when executed, not when sourced (guarded by BASH_SOURCE check).
  source "$SCRIPT"
}

# --- JUnit XML parsing -------------------------------------------------------

@test "parse_junit_xml emits normalized status|id|duration records" {
  run parse_junit_xml "$FIXTURES/junit-run1.xml"
  [ "$status" -eq 0 ]
  # Each testcase becomes one record: status|classname.name|duration
  [ "${lines[0]}" = "passed|math.test_add|0.10" ]
  [ "${lines[1]}" = "passed|math.test_subtract|0.20" ]
  [ "${lines[2]}" = "failed|net.test_connect|0.50" ]
  [ "${lines[3]}" = "skipped|io.test_read|0.00" ]
  [ "${lines[4]}" = "passed|math.test_divide|0.05" ]
}

@test "parse_junit_xml fails with a clear message for a missing file" {
  run parse_junit_xml "$FIXTURES/does-not-exist.xml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file not found"* ]]
}

# --- JSON parsing ------------------------------------------------------------

@test "parse_json emits normalized status|id records" {
  run parse_json "$FIXTURES/results-run3.json"
  [ "$status" -eq 0 ]
  # Assert status|id exactly. The trailing duration's float formatting is left
  # to jq (1.6 prints 0.2, 1.7 preserves 0.20); the numeric value is checked
  # separately below so the test is robust across jq versions.
  [ "${lines[0]%|*}" = "passed|math.test_add" ]
  [ "${lines[1]%|*}" = "passed|math.test_subtract" ]
  [ "${lines[2]%|*}" = "failed|net.test_connect" ]
  [ "${lines[3]%|*}" = "passed|io.test_read" ]
  [ "${lines[4]%|*}" = "failed|api.test_login" ]
  # Duration of the first record is numerically 0.11 regardless of formatting.
  d="${lines[0]##*|}"
  [ "$(awk -v x="$d" 'BEGIN{print (x==0.11)?"ok":"no"}')" = "ok" ]
}

@test "parse_json rejects JSON without a tests array" {
  echo '{"foo": 1}' > "$BATS_TEST_TMPDIR/bad.json"
  run parse_json "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid or unrecognized JSON"* ]]
}

# --- Format dispatch ---------------------------------------------------------

@test "parse_file rejects unsupported extensions" {
  run parse_file "$FIXTURES/whatever.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported file type"* ]]
}

# --- Markdown aggregation: exact totals --------------------------------------

@test "summary computes exact totals across the matrix (3 runs)" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Passed | 9 |"* ]]
  [[ "$output" == *"| Failed | 4 |"* ]]
  [[ "$output" == *"| Skipped | 2 |"* ]]
  [[ "$output" == *"| Total | 15 |"* ]]
  [[ "$output" == *"| Duration | 2.82s |"* ]]
}

@test "summary detects exactly the two flaky tests" {
  run "$SCRIPT" "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Flaky | 2 |"* ]]
  [[ "$output" == *'`math.test_subtract`'* ]]
  [[ "$output" == *'`net.test_connect`'* ]]
  # A test that only ever failed (api.test_login) must NOT be flaky.
  [[ "$output" != *'`api.test_login`'* ]]
  # A test that only ever passed (math.test_add) must NOT be flaky.
  [[ "$output" != *'`math.test_add`'* ]]
}

@test "summary reports overall FAILED when there are failures" {
  run "$SCRIPT" "$FIXTURES"
  [[ "$output" == *"**Result:** FAILED"* ]]
}

@test "summary reports overall PASSED when nothing failed" {
  # All-green fixture: two runs of the same passing test.
  cat > "$BATS_TEST_TMPDIR/green.json" <<'EOF'
{ "tests": [ { "classname": "ok", "name": "t1", "status": "passed", "duration": 0.1 } ] }
EOF
  run "$SCRIPT" "$BATS_TEST_TMPDIR/green.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Result:** PASSED"* ]]
  [[ "$output" == *"None detected."* ]]
}

# --- CLI error handling ------------------------------------------------------

@test "running with no arguments fails with usage" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no input files or directories"* ]]
}

@test "running with a non-existent path fails" {
  run "$SCRIPT" "/no/such/path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"path not found"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: aggregate.sh"* ]]
}

# --- Workflow structure tests ------------------------------------------------

@test "workflow file exists and passes actionlint" {
  WF="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
  [ -f "$WF" ]
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares the expected triggers" {
  WF="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
  run grep -E '^on:' "$WF"
  [ "$status" -eq 0 ]
  for trig in push pull_request workflow_dispatch schedule; do
    grep -qE "^[[:space:]]+${trig}:" "$WF" || {
      echo "missing trigger: $trig"; false
    }
  done
}

@test "workflow declares permissions and a job" {
  WF="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
  grep -qE '^permissions:' "$WF"
  grep -qE '^jobs:' "$WF"
  grep -qE 'actions/checkout@v4' "$WF"
}

@test "workflow references the aggregate.sh script which exists" {
  WF="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
  grep -q 'aggregate.sh' "$WF"
  [ -f "$REPO_ROOT/aggregate.sh" ]
}

@test "workflow references the fixtures directory which exists" {
  WF="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
  grep -q 'fixtures' "$WF"
  [ -d "$REPO_ROOT/fixtures" ]
}
