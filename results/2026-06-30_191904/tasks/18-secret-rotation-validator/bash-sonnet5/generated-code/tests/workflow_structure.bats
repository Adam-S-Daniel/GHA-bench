#!/usr/bin/env bats
# Structural tests for .github/workflows/secret-rotation-validator.yml: parse
# the YAML and assert on its triggers/jobs/steps, confirm every file path it
# references actually exists in the repo, and confirm actionlint is clean.
#
# Note: PyYAML implements YAML 1.1, which coerces the bare top-level `on:`
# key into the Python boolean `True` (the well-known YAML "Norway problem").
# So `data[True]` below is deliberate, not a typo.

setup() {
  repo_root="$BATS_TEST_DIRNAME/.."
  workflow="$repo_root/.github/workflows/secret-rotation-validator.yml"
}

@test "workflow file exists and is valid YAML" {
  run python3 -c "
import yaml
with open('$workflow') as f:
    yaml.safe_load(f)
print('valid')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid"* ]]
}

@test "workflow declares push, pull_request, schedule, and workflow_dispatch triggers" {
  run python3 -c "
import yaml
with open('$workflow') as f:
    data = yaml.safe_load(f)
triggers = data[True]
assert 'push' in triggers, 'missing push trigger'
assert 'pull_request' in triggers, 'missing pull_request trigger'
assert 'schedule' in triggers, 'missing schedule trigger'
assert isinstance(triggers['schedule'], list) and triggers['schedule'][0].get('cron'), 'schedule missing a cron expression'
assert 'workflow_dispatch' in triggers, 'missing workflow_dispatch trigger'
print('triggers ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"triggers ok"* ]]
}

@test "workflow declares minimal read-only permissions" {
  run python3 -c "
import yaml
with open('$workflow') as f:
    data = yaml.safe_load(f)
assert data['permissions']['contents'] == 'read'
print('permissions ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permissions ok"* ]]
}

@test "workflow defines the lint, test, and notify jobs with the expected dependency chain" {
  run python3 -c "
import yaml
with open('$workflow') as f:
    data = yaml.safe_load(f)
jobs = data['jobs']
assert set(jobs.keys()) == {'lint', 'test', 'notify'}, jobs.keys()
assert jobs['test']['needs'] == 'lint'
assert jobs['notify']['needs'] == 'test'
print('jobs ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs ok"* ]]
}

@test "test job exposes expired/warning/ok/total count outputs" {
  run python3 -c "
import yaml
with open('$workflow') as f:
    data = yaml.safe_load(f)
outputs = data['jobs']['test']['outputs']
for key in ('expired_count', 'warning_count', 'ok_count', 'total_count'):
    assert key in outputs, f'missing output {key}'
print('outputs ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"outputs ok"* ]]
}

@test "workflow references secret-rotation-validator.sh and it exists in the repo" {
  run bash -c "grep -c 'secret-rotation-validator.sh' '$workflow'"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  [ -f "$repo_root/secret-rotation-validator.sh" ]
}

@test "every fixture and config path referenced in the workflow exists on disk" {
  for path in secrets-config.json fixtures/secrets-mixed.json fixtures/secrets-all-expired.json; do
    run bash -c "grep -Fq '$path' '$workflow'"
    [ "$status" -eq 0 ]
    [ -f "$repo_root/$path" ]
  done
}

@test "every bats test file referenced in the workflow exists on disk" {
  run python3 -c "
import re
with open('$workflow') as f:
    content = f.read()
paths = re.findall(r'tests/[A-Za-z0-9_./-]+\.bats', content)
assert paths, 'no bats test paths found in workflow'
print('\n'.join(paths))
"
  [ "$status" -eq 0 ]
  while IFS= read -r bats_path; do
    [ -z "$bats_path" ] && continue
    [ -f "$repo_root/$bats_path" ]
  done <<< "$output"
}

@test "actionlint passes on the workflow file" {
  run actionlint "$workflow"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
