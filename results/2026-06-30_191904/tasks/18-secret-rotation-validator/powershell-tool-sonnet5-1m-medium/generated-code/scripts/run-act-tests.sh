#!/usr/bin/env bash
# Drives the secret-rotation-validator.yml workflow through `act` for two
# scenarios, capturing all output to act-result.txt and asserting on exact
# expected values (not just "some output appeared").
#
# Both cases use the same committed fixtures/sample-secrets.json (so the
# CLI's own Pester tests, which hardcode expectations against that file,
# keep passing in every copy). What varies is VALIDATION_NOW in the temp
# copy's workflow file, which changes which secrets are due:
#   1. base    - VALIDATION_NOW=2026-07-01 (committed default)
#                -> 2 Expired, 1 Warning, 1 Ok, 4 Total.
#   2. all-ok  - VALIDATION_NOW=2026-01-15 (patched in the temp copy)
#                -> 0 Expired, 0 Warning, 4 Ok, 4 Total.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"

: > "$RESULT_FILE"

FAILURES=0

run_case() {
    local case_name="$1"
    local validation_now_override="$2" # empty string = keep committed default
    local expected_total="$3"
    local expected_expired="$4"
    local expected_warning="$5"
    local expected_ok="$6"

    echo "=============================================================" | tee -a "$RESULT_FILE"
    echo "TEST CASE: $case_name" | tee -a "$RESULT_FILE"
    echo "=============================================================" | tee -a "$RESULT_FILE"

    local work_dir
    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' RETURN

    # Copy project files (excluding .git and prior act artifacts) into an
    # isolated temp git repo for this test case.
    rsync -a --exclude '.git' --exclude 'act-result.txt' --exclude 'act-work' \
        "$PROJECT_ROOT"/ "$work_dir"/

    if [[ -n "$validation_now_override" ]]; then
        sed -i "s/VALIDATION_NOW: '2026-07-01'/VALIDATION_NOW: '$validation_now_override'/" \
            "$work_dir/.github/workflows/secret-rotation-validator.yml"
    fi

    git -C "$work_dir" init -q
    git -C "$work_dir" -c user.email=test@example.com -c user.name=test add -A
    git -C "$work_dir" -c user.email=test@example.com -c user.name=test commit -q -m "test case: $case_name"

    local act_output
    local act_exit=0
    act_output="$(cd "$work_dir" && act push --rm --pull=false 2>&1)" || act_exit=$?

    {
        echo "--- act exit code: $act_exit ---"
        echo "$act_output"
        echo ""
    } >> "$RESULT_FILE"

    if [[ "$act_exit" -ne 0 ]]; then
        echo "FAIL [$case_name]: act exited with $act_exit, expected 0" | tee -a "$RESULT_FILE"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local job_success_count
    job_success_count="$(grep -c 'Job succeeded' <<<"$act_output" || true)"
    if [[ "$job_success_count" -lt 2 ]]; then
        echo "FAIL [$case_name]: expected 2 'Job succeeded' lines (unit-tests, validate-secrets), found $job_success_count" | tee -a "$RESULT_FILE"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS [$case_name]: both jobs reported 'Job succeeded'" | tee -a "$RESULT_FILE"
    fi

    assert_contains() {
        local label="$1" needle="$2"
        if grep -qF "$needle" <<<"$act_output"; then
            echo "PASS [$case_name]: found exact value for $label ('$needle')" | tee -a "$RESULT_FILE"
        else
            echo "FAIL [$case_name]: expected exact value for $label ('$needle') not found in act output" | tee -a "$RESULT_FILE"
            FAILURES=$((FAILURES + 1))
        fi
    }

    assert_contains "Total"    "Total: $expected_total  |  Expired: $expected_expired  |  Warning: $expected_warning  |  Ok: $expected_ok"
    # actionlint is not installed in the act container, so the workflow's
    # actionlint structural test skips there (1 skip out of 33 discovered).
    assert_contains "Pester summary" "All 32 Pester tests passed."
}

run_case "base"    ""           4 2 1 1
run_case "all-ok"  "2026-01-15" 4 0 0 4

echo "=============================================================" | tee -a "$RESULT_FILE"
if [[ "$FAILURES" -eq 0 ]]; then
    echo "ALL ASSERTIONS PASSED" | tee -a "$RESULT_FILE"
    exit 0
else
    echo "$FAILURES ASSERTION(S) FAILED" | tee -a "$RESULT_FILE"
    exit 1
fi
