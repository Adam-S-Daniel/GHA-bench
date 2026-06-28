#!/usr/bin/env bats
#
# Unit tests for aggregate.sh — the test-results aggregator.
#
# These tests follow red/green TDD: each test was written BEFORE the code that
# makes it pass. They are runnable directly with `bats test/aggregate.bats`
# and are ALSO executed inside the GitHub Actions workflow (via `act`), so the
# exact same cases run through the CI pipeline.

# `run --separate-stderr` requires bats >= 1.5.0.
bats_require_minimum_version 1.5.0

setup() {
    # Resolve paths relative to this test file so the suite works from any CWD
    # (locally and inside the act container).
    TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    REPO_DIR="$( cd "$TEST_DIR/.." && pwd )"
    SCRIPT="$REPO_DIR/aggregate.sh"
    FIXTURES="$TEST_DIR/fixtures"

    # A scratch directory, unique per test, cleaned up in teardown().
    TMP="$( mktemp -d )"
}

teardown() {
    [ -n "$TMP" ] && rm -rf "$TMP"
}

# --- Cycle 1: usage / argument handling ------------------------------------

@test "exits non-zero and prints usage when given no arguments" {
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# --- Cycle 2: parse a single JUnit XML file --------------------------------

@test "aggregates a single JUnit XML file with correct totals" {
    run "$SCRIPT" "$FIXTURES/junit-suite-a.xml"
    [ "$status" -eq 0 ]
    # suite-a: 2 passed, 1 failed, 1 skipped, total 4, duration 1.00s
    [[ "$output" == *"| Total | 4 |"* ]]
    [[ "$output" == *"| Passed | 2 |"* ]]
    [[ "$output" == *"| Failed | 1 |"* ]]
    [[ "$output" == *"| Skipped | 1 |"* ]]
    [[ "$output" == *"| Duration | 1.00s |"* ]]
}

# --- Cycle 3: parse a single JSON file -------------------------------------

@test "aggregates a single JSON file with correct totals" {
    run "$SCRIPT" "$FIXTURES/results-suite-c.json"
    [ "$status" -eq 0 ]
    # suite-c: 2 passed, 1 failed, 0 skipped, total 3, duration 0.49s
    [[ "$output" == *"| Total | 3 |"* ]]
    [[ "$output" == *"| Passed | 2 |"* ]]
    [[ "$output" == *"| Failed | 1 |"* ]]
    [[ "$output" == *"| Skipped | 0 |"* ]]
    [[ "$output" == *"| Duration | 0.49s |"* ]]
}

# --- Cycle 4: aggregate across multiple files (matrix build) ---------------

@test "aggregates totals across all three matrix files" {
    run "$SCRIPT" "$FIXTURES/junit-suite-a.xml" \
                  "$FIXTURES/junit-suite-b.xml" \
                  "$FIXTURES/results-suite-c.json"
    [ "$status" -eq 0 ]
    # Combined: 7 passed, 2 failed, 1 skipped, total 10, duration 2.30s
    [[ "$output" == *"| Total | 10 |"* ]]
    [[ "$output" == *"| Passed | 7 |"* ]]
    [[ "$output" == *"| Failed | 2 |"* ]]
    [[ "$output" == *"| Skipped | 1 |"* ]]
    [[ "$output" == *"| Duration | 2.30s |"* ]]
}

# --- Cycle 5: flaky test detection -----------------------------------------

@test "detects flaky tests that both passed and failed across runs" {
    run "$SCRIPT" "$FIXTURES/junit-suite-a.xml" \
                  "$FIXTURES/junit-suite-b.xml" \
                  "$FIXTURES/results-suite-c.json"
    [ "$status" -eq 0 ]
    # net.Client::test_connect (failed in A, passed in B) is flaky.
    # net.Client::test_retry (skipped in A, passed in B, failed in C) is flaky.
    [[ "$output" == *"| Flaky | 2 |"* ]]
    [[ "$output" == *"net.Client::test_connect"* ]]
    [[ "$output" == *"net.Client::test_retry"* ]]
    # A consistently-passing test must NOT be reported as flaky.
    [[ "$output" != *"math.Calc::test_add |"* ]]
}

# --- Cycle 6: directory input (scan for *.xml and *.json) ------------------

@test "accepts a directory and scans it for result files" {
    run "$SCRIPT" "$FIXTURES"
    [ "$status" -eq 0 ]
    # Scanning the fixtures dir aggregates the same three files.
    [[ "$output" == *"| Total | 10 |"* ]]
    [[ "$output" == *"| Flaky | 2 |"* ]]
}

# --- Cycle 7: markdown structure -------------------------------------------

@test "produces the expected markdown section headers" {
    run "$SCRIPT" "$FIXTURES/junit-suite-a.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Test Results Summary"* ]]
    [[ "$output" == *"## Per-file Breakdown"* ]]
    [[ "$output" == *"## Flaky Tests"* ]]
    [[ "$output" == *"## Result"* ]]
}

@test "reports PASSED verdict when no tests failed" {
    run "$SCRIPT" "$FIXTURES/junit-suite-b.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASSED"* ]]
    [[ "$output" == *"None detected"* ]]
}

# --- Cycle 8: --output flag ------------------------------------------------

@test "--output writes the markdown summary to a file" {
    run "$SCRIPT" --output "$TMP/summary.md" "$FIXTURES/results-suite-c.json"
    [ "$status" -eq 0 ]
    [ -f "$TMP/summary.md" ]
    grep -q "| Total | 3 |" "$TMP/summary.md"
}

# --- Cycle 9: machine-readable summary on stderr ---------------------------

@test "emits a compact machine-readable summary line on stderr" {
    run --separate-stderr "$SCRIPT" "$FIXTURES/junit-suite-a.xml" \
                                    "$FIXTURES/junit-suite-b.xml" \
                                    "$FIXTURES/results-suite-c.json"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"total=10 passed=7 failed=2 skipped=1 flaky=2 duration=2.30s files=3"* ]]
}

# --- Cycle 10: --fail-on-failure -------------------------------------------

@test "--fail-on-failure exits non-zero when a test failed" {
    run "$SCRIPT" --fail-on-failure "$FIXTURES/junit-suite-a.xml"
    [ "$status" -ne 0 ]
    # Markdown is still produced even when failing the run.
    [[ "$output" == *"# Test Results Summary"* ]]
}

@test "--fail-on-failure exits 0 when all tests passed" {
    run "$SCRIPT" --fail-on-failure "$FIXTURES/junit-suite-b.xml"
    [ "$status" -eq 0 ]
}

# --- Cycle 11: error handling ----------------------------------------------

@test "errors on a nonexistent path" {
    run "$SCRIPT" "$TMP/does-not-exist.xml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no such file or directory"* ]]
}

@test "errors on an unknown option" {
    run "$SCRIPT" --bogus "$FIXTURES/junit-suite-a.xml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "errors on a directory containing no result files" {
    mkdir -p "$TMP/empty"
    run "$SCRIPT" "$TMP/empty"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no test result files"* ]]
}

@test "errors on malformed JSON lacking a tests array" {
    echo '{"foo": 1}' > "$TMP/bad.json"
    run "$SCRIPT" "$TMP/bad.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no top-level"* ]] || [[ "$output" == *"tests"* ]]
}

# --- Cycle 12: edge cases in parsing ---------------------------------------

@test "handles a JUnit file whose root is <testsuites>" {
    # suite-b uses the <testsuites> wrapper form.
    run "$SCRIPT" "$FIXTURES/junit-suite-b.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Total | 3 |"* ]]
    [[ "$output" == *"| Passed | 3 |"* ]]
}
