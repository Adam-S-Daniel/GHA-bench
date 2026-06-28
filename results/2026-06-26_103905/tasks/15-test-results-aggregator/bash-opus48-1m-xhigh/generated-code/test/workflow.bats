#!/usr/bin/env bats
#
# Workflow tests:
#   * structural checks on the workflow YAML (triggers / jobs / steps),
#   * that it references the project's script files by paths that exist,
#   * that it passes actionlint cleanly,
#   * and that the act harness produced act-result.txt with the exact
#     expected aggregate values and a succeeding job for every test case.
#
# Run order: execute `bash run-act-tests.sh` BEFORE this suite so that
# act-result.txt exists for the artifact-verification tests below.

bats_require_minimum_version 1.5.0

setup() {
    TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    REPO_DIR="$( cd "$TEST_DIR/.." && pwd )"
    WORKFLOW="$REPO_DIR/.github/workflows/test-results-aggregator.yml"
    ACT_RESULT="$REPO_DIR/act-result.txt"
}

# --- structure -------------------------------------------------------------

@test "workflow file exists" {
    [ -f "$WORKFLOW" ]
}

@test "workflow passes actionlint cleanly" {
    run actionlint "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow declares all expected trigger events" {
    grep -qE '^on:' "$WORKFLOW"
    grep -qE '^[[:space:]]+push:' "$WORKFLOW"
    grep -qE '^[[:space:]]+pull_request:' "$WORKFLOW"
    grep -qE '^[[:space:]]+schedule:' "$WORKFLOW"
    grep -qE '^[[:space:]]+workflow_dispatch:' "$WORKFLOW"
}

@test "workflow declares least-privilege permissions" {
    grep -qE '^permissions:' "$WORKFLOW"
    grep -qE 'contents:[[:space:]]*read' "$WORKFLOW"
}

@test "workflow defines an aggregate job running on ubuntu-latest" {
    grep -qE '^[[:space:]]+aggregate:' "$WORKFLOW"
    grep -qE 'runs-on:[[:space:]]*ubuntu-latest' "$WORKFLOW"
}

@test "workflow uses actions/checkout@v4" {
    grep -qF 'actions/checkout@v4' "$WORKFLOW"
}

@test "workflow references the aggregator script and unit tests" {
    grep -qF 'aggregate.sh' "$WORKFLOW"
    grep -qF 'bats test/aggregate.bats' "$WORKFLOW"
}

@test "workflow writes to the GitHub Actions job summary" {
    grep -qF 'GITHUB_STEP_SUMMARY' "$WORKFLOW"
}

# --- referenced paths actually exist ---------------------------------------

@test "files referenced by the workflow exist on disk" {
    [ -f "$REPO_DIR/aggregate.sh" ]
    [ -f "$REPO_DIR/test/aggregate.bats" ]
}

# --- act artifact verification (requires run-act-tests.sh to have run) -----

@test "act-result.txt artifact exists and is non-empty" {
    [ -s "$ACT_RESULT" ]
}

@test "act-result.txt records every test case and a succeeding job" {
    grep -qF 'TEST CASE: matrix' "$ACT_RESULT"
    grep -qF 'TEST CASE: all-green' "$ACT_RESULT"
    grep -qF 'TEST CASE: flaky' "$ACT_RESULT"
    grep -qF 'Job succeeded' "$ACT_RESULT"
    grep -qF 'ALL ACT TEST ASSERTIONS PASSED' "$ACT_RESULT"
}

@test "act-result.txt shows the exact matrix-case aggregate values" {
    grep -qF 'total=10 passed=7 failed=2 skipped=1 flaky=2 duration=2.30s files=3' "$ACT_RESULT"
}

@test "act-result.txt shows the exact all-green-case aggregate values" {
    grep -qF 'total=3 passed=3 failed=0 skipped=0 flaky=0 duration=2.00s files=1' "$ACT_RESULT"
}

@test "act-result.txt shows the exact flaky-case aggregate values" {
    grep -qF 'total=4 passed=2 failed=2 skipped=0 flaky=2 duration=4.00s files=2' "$ACT_RESULT"
}
