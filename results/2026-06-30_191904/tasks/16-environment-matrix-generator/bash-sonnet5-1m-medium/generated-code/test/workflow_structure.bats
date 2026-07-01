#!/usr/bin/env bats
# Structural tests for the GitHub Actions workflow: YAML shape, script
# references, and actionlint validation. These do not invoke act.

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  WORKFLOW=".github/workflows/environment-matrix-generator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow is valid YAML" {
  python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
}

@test "workflow defines expected trigger events" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
on = doc.get(True) or doc.get('on')
assert 'push' in on, 'missing push trigger'
assert 'pull_request' in on, 'missing pull_request trigger'
assert 'workflow_dispatch' in on, 'missing workflow_dispatch trigger'
assert 'schedule' in on, 'missing schedule trigger'
"
  [ "$status" -eq 0 ]
}

@test "workflow defines expected jobs" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
for name in ['generate', 'build', 'generate-matrix', 'validate-size-limit']:
    assert name in jobs, f'missing job {name}'
"
  [ "$status" -eq 0 ]
}

@test "build job depends on generate job" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc['jobs']['build']['needs'] == 'generate'
"
  [ "$status" -eq 0 ]
}

@test "generate-matrix job runs a fixture-driven job matrix" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
fixtures = doc['jobs']['generate-matrix']['strategy']['matrix']['fixture']
assert fixtures == ['basic', 'exclude_flags_include', 'minimal_defaults'], fixtures
"
  [ "$status" -eq 0 ]
}

@test "workflow declares read-only top-level permissions" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc['permissions']['contents'] == 'read'
"
  [ "$status" -eq 0 ]
}

@test "workflow references matrix-generator.sh which exists in the repo" {
  grep -q 'MATRIX_SCRIPT: matrix-generator.sh' "$WORKFLOW"
  [ -f "matrix-generator.sh" ]
  [ -x "matrix-generator.sh" ]
}

@test "workflow references fixture files that exist in the repo" {
  for f in basic exclude_flags_include minimal_defaults too_big; do
    [ -f "fixtures/${f}.json" ]
    grep -q "fixtures/${f}.json\|${f}\.json\|- ${f}$" "$WORKFLOW" || grep -q "$f" "$WORKFLOW"
  done
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
