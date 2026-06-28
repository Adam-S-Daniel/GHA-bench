#!/usr/bin/env bash
#
# run-act-tests.sh — End-to-end CI harness for the test-results aggregator.
#
# Every test case is executed THROUGH the GitHub Actions workflow via `act`
# (nektos/act); the script is never tested directly here. For each case we:
#
#   1. Build a throwaway git repo containing the project files + that case's
#      fixture data (staged under ./ci-results/, which the workflow auto-detects).
#   2. Run `act push --rm`, capturing all output.
#   3. Append the output to ./act-result.txt, clearly delimited per case.
#   4. Assert act exited 0.
#   5. Assert the job reports "Job succeeded".
#   6. Assert the workflow produced the EXACT expected aggregate values for
#      that case's input (totals, flaky tests, verdict).
#
# Exit status is 0 only if every assertion of every case passed.

set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESULT_FILE="$HERE/act-result.txt"
WORKFLOW=".github/workflows/test-results-aggregator.yml"

# Truncate the aggregate artifact at the start of a run.
: > "$RESULT_FILE"

FAILURES=0
OUT=""        # path to the current case's captured act output
ACT_EXIT=1    # current case's act exit code

# --- assertion helpers -----------------------------------------------------

note() { echo "$*"; echo "$*" >> "$RESULT_FILE"; }

assert_exit_zero() {
    local name="$1"
    if [ "$ACT_EXIT" -eq 0 ]; then
        note "  PASS [$name]: act exited 0"
    else
        note "  FAIL [$name]: act exited $ACT_EXIT (expected 0)"
        FAILURES=$((FAILURES + 1))
    fi
}

# Assert the captured output contains an exact (fixed-string) substring.
assert_has() {
    local name="$1" needle="$2"
    if grep -qF -- "$needle" "$OUT"; then
        note "  PASS [$name]: found \"$needle\""
    else
        note "  FAIL [$name]: missing \"$needle\""
        FAILURES=$((FAILURES + 1))
    fi
}

# Assert the captured output does NOT contain a fixed-string substring.
assert_absent() {
    local name="$1" needle="$2"
    if grep -qF -- "$needle" "$OUT"; then
        note "  FAIL [$name]: unexpectedly found \"$needle\""
        FAILURES=$((FAILURES + 1))
    else
        note "  PASS [$name]: correctly absent \"$needle\""
    fi
}

# --- repo + act plumbing ---------------------------------------------------

# Copy the project into a fresh temp git repo. Echoes the repo path.
setup_repo() {
    local d
    d="$( mktemp -d )"
    cp "$HERE/aggregate.sh" "$d/"
    cp -r "$HERE/test" "$d/"
    mkdir -p "$d/.github/workflows"
    cp "$HERE/$WORKFLOW" "$d/.github/workflows/"
    # Carry the act platform mapping (custom image) into the temp repo.
    [ -f "$HERE/.actrc" ] && cp "$HERE/.actrc" "$d/"
    chmod +x "$d/aggregate.sh"
    mkdir -p "$d/ci-results"
    git -C "$d" init -q
    git -C "$d" config user.email "harness@example.com"
    git -C "$d" config user.name "act harness"
    echo "$d"
}

# Run the workflow under act inside the given repo, capturing output.
run_act() {
    local name="$1" repo="$2"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "fixture: $name"

    note "================================================================"
    note "=== TEST CASE: $name"
    note "================================================================"

    OUT="$( mktemp )"
    ( cd "$repo" && act push --rm --pull=false ) >"$OUT" 2>&1
    ACT_EXIT=$?

    # Persist the full act output for this case into the artifact file.
    cat "$OUT" >> "$RESULT_FILE"
    note "=== act exit code for '$name': $ACT_EXIT"
}

# ===========================================================================
# Test case 1: "matrix" — the canonical three-file matrix build.
#   Expected: total 10, passed 7, failed 2, skipped 1, flaky 2, dur 2.30s.
# ===========================================================================
case_matrix() {
    local repo; repo="$( setup_repo )"
    cp "$HERE/test/fixtures/junit-suite-a.xml" "$repo/ci-results/"
    cp "$HERE/test/fixtures/junit-suite-b.xml" "$repo/ci-results/"
    cp "$HERE/test/fixtures/results-suite-c.json" "$repo/ci-results/"

    run_act "matrix" "$repo"

    assert_exit_zero "matrix"
    assert_has "matrix" "Job succeeded"
    assert_has "matrix" "| Total | 10 |"
    assert_has "matrix" "| Passed | 7 |"
    assert_has "matrix" "| Failed | 2 |"
    assert_has "matrix" "| Skipped | 1 |"
    assert_has "matrix" "| Flaky | 2 |"
    assert_has "matrix" "| Duration | 2.30s |"
    assert_has "matrix" "net.Client::test_connect"
    assert_has "matrix" "net.Client::test_retry"
    # A test that always passed must NOT be reported as flaky.
    assert_absent "matrix" "math.Calc::test_add"
    assert_has "matrix" "total=10 passed=7 failed=2 skipped=1 flaky=2 duration=2.30s files=3"
    assert_has "matrix" "FAILED"
    rm -rf "$repo"
}

# ===========================================================================
# Test case 2: "all-green" — a single all-passing JSON file.
#   Expected: total 3, passed 3, failed 0, skipped 0, flaky 0, dur 2.00s.
# ===========================================================================
case_all_green() {
    local repo; repo="$( setup_repo )"
    cat > "$repo/ci-results/all-green.json" <<'JSON'
{
  "name": "green-suite",
  "tests": [
    { "classname": "a.S", "name": "t1", "status": "passed", "duration": 0.5 },
    { "classname": "a.S", "name": "t2", "status": "passed", "duration": 0.5 },
    { "classname": "a.S", "name": "t3", "status": "passed", "duration": 1.0 }
  ]
}
JSON

    run_act "all-green" "$repo"

    assert_exit_zero "all-green"
    assert_has "all-green" "Job succeeded"
    assert_has "all-green" "| Total | 3 |"
    assert_has "all-green" "| Passed | 3 |"
    assert_has "all-green" "| Failed | 0 |"
    assert_has "all-green" "| Skipped | 0 |"
    assert_has "all-green" "| Flaky | 0 |"
    assert_has "all-green" "| Duration | 2.00s |"
    assert_has "all-green" "total=3 passed=3 failed=0 skipped=0 flaky=0 duration=2.00s files=1"
    assert_has "all-green" "None detected"
    assert_has "all-green" "PASSED"
    rm -rf "$repo"
}

# ===========================================================================
# Test case 3: "flaky" — one JUnit + one JSON file where two tests flip
# pass/fail across the two runs.
#   Expected: total 4, passed 2, failed 2, skipped 0, flaky 2, dur 4.00s.
# ===========================================================================
case_flaky() {
    local repo; repo="$( setup_repo )"
    cat > "$repo/ci-results/run1.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="flaky-run1" tests="2" failures="1" skipped="0" time="2.00">
  <testcase classname="c.T" name="x" time="1.00"/>
  <testcase classname="c.T" name="y" time="1.00">
    <failure message="boom">stack</failure>
  </testcase>
</testsuite>
XML
    cat > "$repo/ci-results/run2.json" <<'JSON'
{
  "name": "flaky-run2",
  "tests": [
    { "classname": "c.T", "name": "x", "status": "failed", "duration": 1.0 },
    { "classname": "c.T", "name": "y", "status": "passed", "duration": 1.0 }
  ]
}
JSON

    run_act "flaky" "$repo"

    assert_exit_zero "flaky"
    assert_has "flaky" "Job succeeded"
    assert_has "flaky" "| Total | 4 |"
    assert_has "flaky" "| Passed | 2 |"
    assert_has "flaky" "| Failed | 2 |"
    assert_has "flaky" "| Skipped | 0 |"
    assert_has "flaky" "| Flaky | 2 |"
    assert_has "flaky" "| Duration | 4.00s |"
    assert_has "flaky" "c.T::x"
    assert_has "flaky" "c.T::y"
    assert_has "flaky" "total=4 passed=2 failed=2 skipped=0 flaky=2 duration=4.00s files=2"
    assert_has "flaky" "FAILED"
    rm -rf "$repo"
}

# --- main ------------------------------------------------------------------

main() {
    if ! command -v act >/dev/null 2>&1; then
        echo "ERROR: 'act' is not installed." >&2
        exit 127
    fi

    # Allow running a single case by name for incremental debugging:
    #   ./run-act-tests.sh matrix
    local only="${1:-all}"
    case "$only" in
        matrix)    case_matrix ;;
        all-green) case_all_green ;;
        flaky)     case_flaky ;;
        all)       case_matrix; case_all_green; case_flaky ;;
        *) echo "Unknown case: $only (use: matrix|all-green|flaky|all)" >&2; exit 2 ;;
    esac

    note ""
    note "================================================================"
    if [ "$FAILURES" -eq 0 ]; then
        note "=== ALL ACT TEST ASSERTIONS PASSED"
        note "================================================================"
        exit 0
    else
        note "=== $FAILURES ACT TEST ASSERTION(S) FAILED"
        note "================================================================"
        exit 1
    fi
}

main "$@"
