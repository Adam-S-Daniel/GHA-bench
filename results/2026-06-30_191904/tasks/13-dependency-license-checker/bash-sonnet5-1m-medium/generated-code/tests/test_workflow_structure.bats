#!/usr/bin/env bats
# Structural checks for the GitHub Actions workflow itself: valid YAML,
# expected triggers/jobs/steps, correct file references, and a clean
# actionlint run.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WORKFLOW="${ROOT}/.github/workflows/dependency-license-checker.yml"
}

@test "workflow file exists and is valid YAML" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request, schedule, and workflow_dispatch triggers" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get(True, doc.get('on'))
assert 'push' in on, 'missing push trigger'
assert 'pull_request' in on, 'missing pull_request trigger'
assert 'schedule' in on, 'missing schedule trigger'
assert 'workflow_dispatch' in on, 'missing workflow_dispatch trigger'
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "workflow defines unit-tests and license-check jobs with a dependency between them" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
assert 'unit-tests' in jobs
assert 'license-check' in jobs
needs = jobs['license-check'].get('needs')
assert needs == 'unit-tests' or needs == ['unit-tests'], needs
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "workflow declares read-only top-level permissions" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc['permissions'] == {'contents': 'read'}
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "workflow references check-licenses.sh and it exists on disk" {
  grep -q 'check-licenses.sh' "$WORKFLOW"
  [ -f "${ROOT}/check-licenses.sh" ]
  [ -x "${ROOT}/check-licenses.sh" ]
}

@test "workflow references lib/license_checker.sh indirectly and it exists on disk" {
  [ -f "${ROOT}/lib/license_checker.sh" ]
}

@test "workflow references fixture and scenario files that exist on disk" {
  grep -q 'fixtures/license-db.json' "$WORKFLOW"
  grep -q 'fixtures/license-config.json' "$WORKFLOW"
  grep -q 'scenario/package.json' "$WORKFLOW"
  [ -f "${ROOT}/fixtures/license-db.json" ]
  [ -f "${ROOT}/fixtures/license-config.json" ]
  [ -f "${ROOT}/scenario/package.json" ]
}

@test "actionlint passes cleanly on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
