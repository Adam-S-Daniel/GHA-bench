#!/usr/bin/env bats
#
# Workflow harness for dependency-license-checker.yml.
#
# Two layers:
#   1. Structure tests (fast, no act): actionlint + a YAML-structure validator
#      confirm the workflow's triggers, jobs, steps and referenced file paths.
#   2. Integration tests (act): for each fixture case, a throwaway git repo is
#      assembled with the project files + that case's manifest/license-db, the
#      workflow is executed with `act push --rm`, the full output is appended to
#      act-result.txt, and we assert on act's exit code, the EXACT report values
#      for that input, and that every job reports "Job succeeded".
#
# Every test case is exercised *through the pipeline* (act), never by calling
# the script directly.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WORKFLOW="${PROJECT_ROOT}/.github/workflows/dependency-license-checker.yml"
ACT_RESULT="${PROJECT_ROOT}/act-result.txt"
ACT_IMAGE="act-ubuntu-pwsh:latest"

# Start each full run with a fresh artifact file.
setup_file() {
    : > "${PROJECT_ROOT}/act-result.txt"
}

# ---------------------------------------------------------------------------
# Structure tests (no act)
# ---------------------------------------------------------------------------

@test "structure: actionlint passes on the workflow" {
    run actionlint "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "structure: workflow declares push/pull_request/schedule/workflow_dispatch" {
    run python3 "${BATS_TEST_DIRNAME}/check_workflow.py" triggers "$WORKFLOW" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:* ]]
}

@test "structure: jobs exist with correct dependency and least-privilege perms" {
    run python3 "${BATS_TEST_DIRNAME}/check_workflow.py" jobs "$WORKFLOW" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:* ]]
}

@test "structure: steps use checkout@v4 and run bats/shellcheck/license-checker.sh" {
    run python3 "${BATS_TEST_DIRNAME}/check_workflow.py" steps "$WORKFLOW" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:* ]]
}

@test "structure: workflow only references files that actually exist" {
    run python3 "${BATS_TEST_DIRNAME}/check_workflow.py" paths "$WORKFLOW" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:* ]]
}

# ---------------------------------------------------------------------------
# act integration helper
# ---------------------------------------------------------------------------
# Assemble a throwaway git repo for $1 (a directory under tests/cases/),
# execute the workflow via act, append the output to act-result.txt, echo the
# output, and return act's exit code.
run_act_case() {
    local case="$1"
    local wd
    wd="$(mktemp -d)"

    # Core project files the workflow depends on.
    cp "${PROJECT_ROOT}/license-checker.sh" "$wd/"
    mkdir -p "$wd/config" "$wd/fixtures" "$wd/tests" "$wd/.github/workflows"
    cp "${PROJECT_ROOT}/config/license-policy.conf" "$wd/config/"
    cp "${PROJECT_ROOT}/tests/license-checker.bats" "$wd/tests/"
    cp "$WORKFLOW" "$wd/.github/workflows/"

    # This case's fixture data (manifest + mock license database).
    cp "${PROJECT_ROOT}/tests/cases/${case}/license-db.txt" "$wd/fixtures/license-db.txt"
    if [ -f "${PROJECT_ROOT}/tests/cases/${case}/requirements.txt" ]; then
        cp "${PROJECT_ROOT}/tests/cases/${case}/requirements.txt" "$wd/fixtures/requirements.txt"
    else
        cp "${PROJECT_ROOT}/tests/cases/${case}/package.json" "$wd/fixtures/package.json"
    fi

    # A committed repo is required for actions/checkout to succeed under act.
    git -C "$wd" init -q -b main
    git -C "$wd" add -A
    git -C "$wd" -c user.email=ci@example.com -c user.name=ci commit -qm "fixture: ${case}" >/dev/null

    local out="$wd/act-output.txt"
    local rc=0
    (
        cd "$wd" && act push --rm --pull=false -P "ubuntu-latest=${ACT_IMAGE}"
    ) >"$out" 2>&1 || rc=$?

    {
        echo "##############################################################################"
        echo "### ACT TEST CASE: ${case}"
        echo "### command: act push --rm --pull=false -P ubuntu-latest=${ACT_IMAGE}"
        echo "### act exit code: ${rc}"
        echo "##############################################################################"
        cat "$out"
        echo ""
    } >> "$ACT_RESULT"

    cat "$out"
    rm -rf "$wd"
    return "$rc"
}

# Count "Job succeeded" markers in the captured act output.
job_success_count() {
    printf '%s\n' "$1" | grep -c 'Job succeeded'
}

# ---------------------------------------------------------------------------
# act integration tests (one act run per case)
# ---------------------------------------------------------------------------

@test "act: approved package.json -> all APPROVED, both jobs succeed" {
    run run_act_case approved
    [ "$status" -eq 0 ]                                        # act exited 0
    # Exact summary for this known input.
    printf '%s\n' "$output" | grep -F "Summary: 3 dependencies, 3 approved, 0 denied, 0 unknown"
    # Exact per-dependency statuses.
    printf '%s\n' "$output" | grep -E 'express[[:space:]].*MIT[[:space:]].*APPROVED'
    printf '%s\n' "$output" | grep -E 'commander[[:space:]].*MIT[[:space:]].*APPROVED'
    printf '%s\n' "$output" | grep -E 'eslint[[:space:]].*ISC[[:space:]].*APPROVED'
    # Both jobs (lint-and-test, license-check) succeeded.
    [ "$(job_success_count "$output")" -ge 2 ]
    ! printf '%s\n' "$output" | grep -q 'Job failed'
}

@test "act: denied package.json -> APPROVED/DENIED/UNKNOWN mix, jobs succeed" {
    run run_act_case denied
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F "Summary: 3 dependencies, 1 approved, 1 denied, 1 unknown"
    printf '%s\n' "$output" | grep -E 'react[[:space:]].*MIT[[:space:]].*APPROVED'
    printf '%s\n' "$output" | grep -E 'agpl-pkg[[:space:]].*AGPL-3\.0[[:space:]].*DENIED'
    printf '%s\n' "$output" | grep -E 'secret-internal[[:space:]].*unknown[[:space:]].*UNKNOWN'
    # The policy-gate step's plain count line (report-only mode: job still succeeds).
    printf '%s\n' "$output" | grep -F "Denied: 1, Unknown: 1"
    [ "$(job_success_count "$output")" -ge 2 ]
    ! printf '%s\n' "$output" | grep -q 'Job failed'
}

@test "act: requirements.txt -> Python manifest parsed, exact statuses, jobs succeed" {
    run run_act_case requirements
    [ "$status" -eq 0 ]
    # The workflow auto-detected the Python manifest.
    printf '%s\n' "$output" | grep -F "Resolved manifest: fixtures/requirements.txt"
    printf '%s\n' "$output" | grep -F "Summary: 4 dependencies, 2 approved, 1 denied, 1 unknown"
    printf '%s\n' "$output" | grep -E 'flask[[:space:]].*BSD-3-Clause[[:space:]].*APPROVED'
    printf '%s\n' "$output" | grep -E 'requests[[:space:]].*Apache-2\.0[[:space:]].*APPROVED'
    printf '%s\n' "$output" | grep -E 'gpl-python-lib[[:space:]].*GPL-3\.0[[:space:]].*DENIED'
    printf '%s\n' "$output" | grep -E 'some-internal-pkg[[:space:]].*unknown[[:space:]].*UNKNOWN'
    [ "$(job_success_count "$output")" -ge 2 ]
    ! printf '%s\n' "$output" | grep -q 'Job failed'
}
