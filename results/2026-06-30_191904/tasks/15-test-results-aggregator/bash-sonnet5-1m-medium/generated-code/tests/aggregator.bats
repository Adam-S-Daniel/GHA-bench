#!/usr/bin/env bats
# tests/aggregator.bats
#
# TDD suite for test-results-aggregator.sh, built in red/green phases:
#   Phase 1: usage/error handling            -> drives usage() + validation
#   Phase 2: JUnit XML parsing                -> drives parse_junit()
#   Phase 3: JSON parsing                     -> drives parse_json()
#   Phase 4: multi-file aggregation           -> drives the accumulation loop
#   Phase 5: flaky test detection             -> drives detect_flaky()
#   Phase 6: markdown summary structure       -> drives the report renderer
#
# This suite is executed by the "Run unit tests" step of
# .github/workflows/test-results-aggregator.yml, so it runs through `act`
# together with the rest of the pipeline (see run-tests.sh for the outer
# act-based integration harness and its exact-value assertions).

SCRIPT="${BATS_TEST_DIRNAME}/../test-results-aggregator.sh"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

# ---------------------------------------------------------------------------
# Phase 1: usage / error handling
# ---------------------------------------------------------------------------

@test "fails with no arguments and prints usage" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fails when an input file does not exist" {
    run bash "$SCRIPT" /nonexistent/does-not-exist.xml
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "fails on an unsupported file extension" {
    local tmpfile
    tmpfile="$(mktemp /tmp/aggXXXXXX.txt)"
    echo "not a result file" > "$tmpfile"
    run bash "$SCRIPT" "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported"* ]]
}

# ---------------------------------------------------------------------------
# Phase 2: JUnit XML parsing
# ---------------------------------------------------------------------------

@test "JUnit XML: passed count" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Passed | 2 |"* ]]
}

@test "JUnit XML: failed count" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Failed | 1 |"* ]]
}

@test "JUnit XML: skipped count" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Skipped | 1 |"* ]]
}

@test "JUnit XML: total test count" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Total Tests | 4 |"* ]]
}

# ---------------------------------------------------------------------------
# Phase 3: JSON parsing
# ---------------------------------------------------------------------------

@test "JSON: passed count" {
    run bash "$SCRIPT" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Passed | 2 |"* ]]
}

@test "JSON: failed count" {
    run bash "$SCRIPT" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Failed | 1 |"* ]]
}

@test "JSON: skipped count is zero" {
    run bash "$SCRIPT" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Skipped | 0 |"* ]]
}

# ---------------------------------------------------------------------------
# Phase 4: multi-file aggregation across matrix runs
# ---------------------------------------------------------------------------

@test "aggregation: files processed count" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Files Processed | 3 |"* ]]
}

@test "aggregation: total test instances across all files" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Total Tests | 11 |"* ]]
}

@test "aggregation: total passed across all files" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Passed | 6 |"* ]]
}

@test "aggregation: total failed across all files" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Failed | 3 |"* ]]
}

@test "aggregation: total skipped across all files" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml" "${FIXTURES}/results-macos.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Skipped | 2 |"* ]]
}

# ---------------------------------------------------------------------------
# Phase 5: flaky test detection
# ---------------------------------------------------------------------------

@test "flaky: TestLogout (passed ubuntu, failed windows) is reported" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"core.TestLogout"* ]]
}

@test "flaky: TestPayment (failed ubuntu, passed windows) is reported" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"core.TestPayment"* ]]
}

@test "flaky: consistently-passing TestLogin is not reported as flaky" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"core.TestLogin | Passed"* ]]
}

@test "flaky: single file reports no flaky tests" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No flaky tests detected"* ]]
}

# ---------------------------------------------------------------------------
# Phase 6: markdown summary structure
# ---------------------------------------------------------------------------

@test "summary: has top-level header" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"# Test Results Summary"* ]]
}

@test "summary: has Overview section" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Overview"* ]]
}

@test "summary: has Flaky Tests section" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Flaky Tests"* ]]
}

@test "summary: shows FAILED status when a run has failures" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Status: FAILED"* ]]
}

@test "summary: shows PASSED status when nothing failed" {
    run bash "$SCRIPT" "${FIXTURES}/all-passing.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Status: PASSED"* ]]
}

@test "summary: total duration is summed across files" {
    run bash "$SCRIPT" "${FIXTURES}/junit-ubuntu.xml" "${FIXTURES}/junit-windows.xml"
    [ "$status" -eq 0 ]
    # ubuntu 0.10+0.12+0.30+0.00 = 0.52 ; windows 0.11+0.14+0.28+0.00 = 0.53 ; total 1.05
    [[ "$output" == *"| Duration | 1.05s |"* ]]
}
