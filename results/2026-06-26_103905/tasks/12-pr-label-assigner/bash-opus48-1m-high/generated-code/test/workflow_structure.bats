#!/usr/bin/env bats
#
# Workflow STRUCTURE tests.
#
# These parse the YAML and assert on the expected shape of the workflow
# (triggers, jobs, steps), confirm it references the script/fixtures that
# actually exist on disk, and confirm actionlint passes. They do NOT run act
# (that lives in workflow_act.bats), so they stay fast.

setup() {
    PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    WF="${PROJECT_DIR}/.github/workflows/pr-label-assigner.yml"
}

# yq(): tiny helper that runs a python snippet over the parsed workflow.
# The snippet receives the parsed document as the variable `d`.
yq() {
    python3 - "$WF" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
d = doc
ns = {"d": d}
exec("print(" + sys.argv[2] + ")", ns)
PY
}

@test "workflow file exists and is valid YAML" {
    [ -f "$WF" ]
    run python3 -c "import yaml,sys; yaml.safe_load(open('$WF')); print('ok')"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow has a name" {
    run yq "d['name']"
    [ "$status" -eq 0 ]
    [ "$output" = "PR Label Assigner" ]
}

@test "workflow triggers on push, pull_request and workflow_dispatch" {
    # PyYAML parses the bare 'on:' key as the boolean True.
    run yq "sorted(k for k in d[True].keys())"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pull_request"* ]]
    [[ "$output" == *"push"* ]]
    [[ "$output" == *"workflow_dispatch"* ]]
}

@test "workflow declares least-privilege permissions" {
    run yq "d['permissions']['contents']"
    [ "$status" -eq 0 ]
    [ "$output" = "read" ]
    run yq "d['permissions']['pull-requests']"
    [ "$status" -eq 0 ]
    [ "$output" = "write" ]
}

@test "workflow sets the RULES_FILE environment variable" {
    run yq "d['env']['RULES_FILE']"
    [ "$status" -eq 0 ]
    [ "$output" = "label-rules.conf" ]
}

@test "workflow defines an 'assign' and a 'summary' job" {
    run yq "sorted(d['jobs'].keys())"
    [ "$status" -eq 0 ]
    [ "$output" = "['assign', 'summary']" ]
}

@test "the summary job depends on the assign job (job dependency)" {
    run yq "d['jobs']['summary']['needs']"
    [ "$status" -eq 0 ]
    [ "$output" = "assign" ]
}

@test "the assign job runs a matrix over all five fixtures" {
    run yq "sorted(d['jobs']['assign']['strategy']['matrix']['fixture'])"
    [ "$status" -eq 0 ]
    [ "$output" = "['api-tests', 'config-tie', 'docs-only', 'mixed', 'no-match']" ]
}

@test "the assign job uses actions/checkout@v4" {
    run yq "[s.get('uses') for s in d['jobs']['assign']['steps'] if 'uses' in s]"
    [ "$status" -eq 0 ]
    [[ "$output" == *"actions/checkout@v4"* ]]
}

@test "the assign job invokes label-assigner.sh" {
    run yq "any('label-assigner.sh' in (s.get('run') or '') for s in d['jobs']['assign']['steps'])"
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "referenced script and rules files actually exist on disk" {
    [ -f "${PROJECT_DIR}/label-assigner.sh" ]
    [ -f "${PROJECT_DIR}/label-rules.conf" ]
}

@test "every matrix fixture has a corresponding fixture file on disk" {
    for fx in docs-only api-tests mixed config-tie no-match; do
        [ -f "${PROJECT_DIR}/fixtures/${fx}.files" ]
    done
}

@test "actionlint validates the workflow (exit 0)" {
    run actionlint "$WF"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
