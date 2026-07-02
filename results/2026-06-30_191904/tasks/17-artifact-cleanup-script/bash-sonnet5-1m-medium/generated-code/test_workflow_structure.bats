#!/usr/bin/env bats
#
# Structural checks on the workflow YAML itself: triggers, jobs, steps, and
# that it references real files in this repo. Complements test_act.bats,
# which verifies the workflow actually *runs* correctly.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  WORKFLOW="$SCRIPT_DIR/.github/workflows/artifact-cleanup-script.yml"
}

@test "workflow file exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run jq -e . <(yq -o=json "$WORKFLOW" 2>/dev/null || python3 -c "import yaml,sys,json; json.dump(yaml.safe_load(open('$WORKFLOW')), sys.stdout)")
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request, schedule and workflow_dispatch triggers" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get(True) or doc.get('on')
assert 'push' in on, 'missing push trigger'
assert 'pull_request' in on, 'missing pull_request trigger'
assert 'schedule' in on, 'missing schedule trigger'
assert 'workflow_dispatch' in on, 'missing workflow_dispatch trigger'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "workflow defines test, cleanup and report jobs with the expected dependency chain" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
assert 'test' in jobs
assert 'cleanup' in jobs
assert 'report' in jobs
assert jobs['cleanup']['needs'] == 'test'
assert jobs['report']['needs'] == 'cleanup'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "workflow declares least-privilege permissions" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc['permissions'] == {'contents': 'read'}
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "workflow references artifact_cleanup.sh and test_artifact_cleanup.bats, which exist in the repo" {
  grep -q 'artifact_cleanup.sh' "$WORKFLOW"
  grep -q 'test_artifact_cleanup.bats' "$WORKFLOW"
  [ -f "$SCRIPT_DIR/artifact_cleanup.sh" ]
  [ -f "$SCRIPT_DIR/test_artifact_cleanup.bats" ]
}

@test "workflow uses actions/checkout@v4 in every job" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
for name, job in doc['jobs'].items():
    steps = job.get('steps', [])
    if name == 'report':
        continue
    uses = [s.get('uses') for s in steps]
    assert 'actions/checkout@v4' in uses, f'{name} missing checkout@v4'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "actionlint passes cleanly on the workflow" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fixtures referenced by the workflow's default ARTIFACTS_DIR exist" {
  [ -f "$SCRIPT_DIR/fixtures/artifacts.json" ]
  [ -f "$SCRIPT_DIR/fixtures/policy.json" ]
}
