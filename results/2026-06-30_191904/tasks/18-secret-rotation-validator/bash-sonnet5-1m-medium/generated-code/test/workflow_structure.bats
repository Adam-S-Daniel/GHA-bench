#!/usr/bin/env bats
# Structural tests for the GitHub Actions workflow: valid YAML, expected
# triggers/jobs/steps, correct references to script/fixture paths, and a
# clean actionlint pass. None of these invoke `act` -- they are fast,
# static checks that should run on every commit.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/.."
  WORKFLOW="${REPO_ROOT}/.github/workflows/secret-rotation-validator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow is valid YAML parseable by yq/jq via python" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request, schedule and workflow_dispatch triggers" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get('on') or doc.get(True)
assert 'push' in on, 'missing push trigger'
assert 'pull_request' in on, 'missing pull_request trigger'
assert 'schedule' in on, 'missing schedule trigger'
assert 'workflow_dispatch' in on, 'missing workflow_dispatch trigger'
"
  [ "$status" -eq 0 ]
}

@test "workflow defines a validate job with permissions and steps" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
assert 'validate' in jobs, 'missing validate job'
job = jobs['validate']
assert 'runs-on' in job
assert len(job['steps']) >= 5, 'expected multiple test-case steps'
assert doc.get('permissions', {}).get('contents') == 'read'
"
  [ "$status" -eq 0 ]
}

@test "workflow references the validator script that actually exists" {
  run grep -c 'scripts/secret_rotation_validator.sh' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -f "${REPO_ROOT}/scripts/secret_rotation_validator.sh" ]
}

@test "workflow references fixture files that actually exist" {
  for fixture in secrets_mixed.json secrets_edge_boundary.json secrets_all_ok.json secrets_invalid.json; do
    run grep -c "fixtures/${fixture}" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ -f "${REPO_ROOT}/fixtures/${fixture}" ]
  done
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
