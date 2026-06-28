#!/usr/bin/env bats
#
# structure.bats
# --------------
# Static checks on the workflow file itself: it must parse, declare the
# expected triggers / jobs / steps, reference the real script + fixtures, and
# pass actionlint cleanly. These run instantly (no act needed).

PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WF="${PROJECT_DIR}/.github/workflows/pr-label-assigner.yml"

@test "workflow file exists" {
    [ -f "${WF}" ]
}

@test "workflow is valid YAML" {
    if command -v python3 >/dev/null 2>&1; then
        run python3 -c "import yaml,sys; yaml.safe_load(open('${WF}'))"
        [ "${status}" -eq 0 ]
    else
        skip "python3 not available to parse YAML"
    fi
}

@test "actionlint passes with exit code 0" {
    run actionlint "${WF}"
    [ "${status}" -eq 0 ]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
    grep -qE '^\s*push:' "${WF}"
    grep -qE '^\s*pull_request:' "${WF}"
    grep -qE '^\s*workflow_dispatch:' "${WF}"
}

@test "workflow declares lint and assign jobs with a dependency" {
    grep -qE '^\s{2}lint:' "${WF}"
    grep -qE '^\s{2}assign:' "${WF}"
    grep -qE 'needs:\s*lint' "${WF}"
}

@test "workflow sets least-privilege permissions" {
    grep -qE 'contents:\s*read' "${WF}"
    grep -qE 'pull-requests:\s*write' "${WF}"
}

@test "workflow uses actions/checkout@v4" {
    grep -q 'actions/checkout@v4' "${WF}"
}

@test "workflow references the label-assigner.sh script which exists" {
    grep -q 'label-assigner.sh' "${WF}"
    [ -f "${PROJECT_DIR}/label-assigner.sh" ]
}

@test "workflow references the rules file which exists" {
    grep -qE 'RULES_FILE:\s*rules.conf' "${WF}"
    [ -f "${PROJECT_DIR}/rules.conf" ]
}

@test "every fixture referenced by the matrix exists on disk" {
    for f in mixed docs-only none; do
        [ -f "${PROJECT_DIR}/fixtures/${f}.txt" ]
    done
}

@test "the script itself passes bash -n and shellcheck" {
    run bash -n "${PROJECT_DIR}/label-assigner.sh"
    [ "${status}" -eq 0 ]
    if command -v shellcheck >/dev/null 2>&1; then
        run shellcheck "${PROJECT_DIR}/label-assigner.sh"
        [ "${status}" -eq 0 ]
    fi
}
