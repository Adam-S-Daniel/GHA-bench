#!/usr/bin/env bats
# Test suite for the semantic version bumper GitHub Actions pipeline.
#
# Per the task spec, every FUNCTIONAL test case drives the real workflow
# through `act push` (never the script directly) — see test_helper.bash's
# run_pipeline_case. Static structure/lint checks run separately and don't
# invoke the pipeline at all.

load 'test_helper'

setup_file() {
    # One act-result.txt per suite run; each pipeline case appends its own
    # clearly delimited section below.
    : > "${ACT_RESULT_FILE}"
}

# ---------------------------------------------------------------------------
# Pipeline (act-driven) test cases — one per conventional-commit bump type.
# ---------------------------------------------------------------------------

@test "pipeline: fix-only commits bump the patch version (1.0.0 -> 1.0.1)" {
    run_pipeline_case "patch" "1.0.0" "commits-patch.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Current version: 1.0.0"* ]]
    [[ "$output" == *"Bump type: patch"* ]]
    [[ "$output" == *"New version: 1.0.1"* ]]
    [ "$(grep -c 'Job succeeded' <<< "$output")" -eq 2 ]
}

@test "pipeline: a feat commit bumps the minor version (1.0.0 -> 1.1.0)" {
    run_pipeline_case "minor" "1.0.0" "commits-minor.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Current version: 1.0.0"* ]]
    [[ "$output" == *"Bump type: minor"* ]]
    [[ "$output" == *"New version: 1.1.0"* ]]
    [ "$(grep -c 'Job succeeded' <<< "$output")" -eq 2 ]
}

@test "pipeline: a breaking-change commit bumps the major version (1.0.0 -> 2.0.0)" {
    run_pipeline_case "major" "1.0.0" "commits-major.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Current version: 1.0.0"* ]]
    [[ "$output" == *"Bump type: major"* ]]
    [[ "$output" == *"New version: 2.0.0"* ]]
    [ "$(grep -c 'Job succeeded' <<< "$output")" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Workflow structure tests — static checks, no act invocation.
# ---------------------------------------------------------------------------

@test "structure: workflow YAML has the expected triggers/jobs/steps" {
    run python3 "${BATS_TEST_DIRNAME}/check_workflow_structure.py" \
        "${PROJECT_ROOT}/.github/workflows/semantic-version-bumper.yml"
    [ "$status" -eq 0 ]
}

@test "structure: workflow references bump_version.sh and it exists on disk" {
    [ -f "${PROJECT_ROOT}/bump_version.sh" ]
    grep -q "bump_version.sh" "${PROJECT_ROOT}/.github/workflows/semantic-version-bumper.yml"
}

@test "structure: actionlint passes on the workflow file" {
    run actionlint "${PROJECT_ROOT}/.github/workflows/semantic-version-bumper.yml"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "artifact: act-result.txt exists and records all three test cases" {
    [ -f "${ACT_RESULT_FILE}" ]
    grep -q "TEST CASE: patch" "${ACT_RESULT_FILE}"
    grep -q "TEST CASE: minor" "${ACT_RESULT_FILE}"
    grep -q "TEST CASE: major" "${ACT_RESULT_FILE}"
}
