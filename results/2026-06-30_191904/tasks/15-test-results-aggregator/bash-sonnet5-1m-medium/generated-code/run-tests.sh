#!/usr/bin/env bash
# run-tests.sh
#
# Outer integration harness. For each test case: sets up an isolated git
# repo containing this project, runs the real GitHub Actions workflow with
# `act push --rm`, and appends the captured output to act-result.txt. Then
# asserts on EXACT expected values parsed from that output (not just that
# some output appeared).
#
# Usage: bash run-tests.sh
# Requires: act, docker, git
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACT_RESULT="${SCRIPT_DIR}/act-result.txt"

: > "$ACT_RESULT"

log() {
    echo "$*" | tee -a "$ACT_RESULT"
}

assert_contains() {
    local expected="$1"
    if grep -qF "$expected" "$ACT_RESULT"; then
        echo "ASSERT PASS: '${expected}'"
    else
        echo "ASSERT FAIL: expected to find '${expected}' in act output" >&2
        exit 1
    fi
}

assert_not_contains() {
    local unexpected="$1"
    if grep -qF "$unexpected" "$ACT_RESULT"; then
        echo "ASSERT FAIL: did not expect to find '${unexpected}' in act output" >&2
        exit 1
    else
        echo "ASSERT PASS (absent): '${unexpected}'"
    fi
}

# Set up a fresh git repo, copy the project into it (optionally overriding
# fixture files for the scenario under test), run act, capture output.
run_act_test() {
    local test_name="$1"
    local tmpdir
    tmpdir="$(mktemp -d)"

    log ""
    log "========================================"
    log "TEST CASE: ${test_name}"
    log "========================================"

    cp -r "${SCRIPT_DIR}/." "${tmpdir}/"

    cd "$tmpdir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Runner"
    git add -A
    git commit -q -m "test: ${test_name}"

    local act_exit=0
    act push --rm --pull=false 2>&1 | tee -a "$ACT_RESULT" || act_exit=$?

    cd "$SCRIPT_DIR"
    rm -rf "$tmpdir"

    if [[ $act_exit -ne 0 ]]; then
        log ""
        log "FAIL: act exited with code ${act_exit} for test case: ${test_name}"
        exit 1
    fi

    log "ACT EXIT CODE: 0"
}

# ---------------------------------------------------------------------------
# Test Case 1: mixed matrix (junit x2 + json) - aggregation + flaky detection
# ---------------------------------------------------------------------------
run_act_test "mixed-matrix-with-flaky-tests"

log ""
log "=== ASSERTIONS: mixed-matrix-with-flaky-tests ==="

# Exact aggregation totals across all 3 fixture files (11 test instances:
# 4 junit-ubuntu + 4 junit-windows + 3 json-macos).
assert_contains "| Files Processed | 3 |"
assert_contains "| Total Tests | 11 |"
assert_contains "| Passed | 6 |"
assert_contains "| Failed | 3 |"
assert_contains "| Skipped | 2 |"
assert_contains "| Duration | 2.73s |"

# Exact overall status given failures are present.
assert_contains "Status: FAILED"

# Exact flaky tests: TestLogout and TestPayment flip between ubuntu/windows legs.
assert_contains "core.TestLogout"
assert_contains "core.TestPayment"

# Every bats assertion in the "test" job ran and passed (34 tests total,
# no "not ok" lines anywhere in the captured output).
assert_contains "1..34"

# Both jobs completed successfully, and no bats assertion failed.
assert_contains "Job succeeded"
assert_not_contains "not ok"

log ""
log "All assertions passed for mixed-matrix-with-flaky-tests!"
