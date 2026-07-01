#!/usr/bin/env bats
# tests/workflow-structure.bats
#
# Static structure checks for the GitHub Actions workflow: triggers, jobs,
# script/fixture references, and actionlint validation. These do not invoke
# `act` (that is covered by run-tests.sh's live pipeline runs); they check
# the workflow file itself is well-formed and wired up correctly.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
WORKFLOW="${REPO_ROOT}/.github/workflows/test-results-aggregator.yml"

@test "workflow file exists" {
    [ -f "$WORKFLOW" ]
}

@test "workflow YAML parses cleanly" {
    run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow declares push trigger" {
    run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get(True, doc.get('on'))
assert 'push' in on, on
"
    [ "$status" -eq 0 ]
}

@test "workflow declares workflow_dispatch trigger" {
    run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get(True, doc.get('on'))
assert 'workflow_dispatch' in on, on
"
    [ "$status" -eq 0 ]
}

@test "workflow has at least one job with a checkout step and run steps" {
    run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
assert len(jobs) >= 1
job = next(iter(jobs.values()))
steps = job['steps']
assert any('actions/checkout' in s.get('uses', '') for s in steps), steps
assert any('run' in s for s in steps), steps
"
    [ "$status" -eq 0 ]
}

@test "workflow references the aggregator script that exists on disk" {
    run grep -o 'test-results-aggregator\.sh' "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ -f "${REPO_ROOT}/test-results-aggregator.sh" ]
}

@test "workflow references fixture files that exist on disk" {
    for fixture in junit-ubuntu.xml junit-windows.xml results-macos.json; do
        run grep -q "fixtures/${fixture}" "$WORKFLOW"
        [ "$status" -eq 0 ]
        [ -f "${REPO_ROOT}/fixtures/${fixture}" ]
    done
}

@test "workflow declares contents:read permissions" {
    run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc.get('permissions', {}).get('contents') == 'read'
"
    [ "$status" -eq 0 ]
}

@test "workflow passes actionlint" {
    run actionlint "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
