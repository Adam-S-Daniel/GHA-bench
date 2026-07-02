#!/usr/bin/env bats
# Static structural checks on the GitHub Actions workflow file itself,
# without invoking act. Complements the act-driven end-to-end run.

setup() {
  WF="$BATS_TEST_DIRNAME/../.github/workflows/pr-label-assigner.yml"
  ROOT="$BATS_TEST_DIRNAME/.."
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "workflow YAML parses successfully" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares expected trigger events" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WF'))
on = doc.get(True) or doc.get('on')
assert 'push' in on
assert 'pull_request' in on
assert 'workflow_dispatch' in on
assert 'schedule' in on
"
  [ "$status" -eq 0 ]
}

@test "workflow declares test and assign-labels jobs with dependency" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WF'))
jobs = doc['jobs']
assert 'test' in jobs
assert 'assign-labels' in jobs
needs = jobs['assign-labels'].get('needs')
assert needs == 'test', needs
"
  [ "$status" -eq 0 ]
}

@test "workflow references the label assigner script that exists on disk" {
  run grep -q "scripts/label_assigner.sh" "$WF"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/scripts/label_assigner.sh" ]
}

@test "workflow references the bats test file that exists on disk" {
  run grep -q "tests/label_assigner.bats" "$WF"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/tests/label_assigner.bats" ]
}

@test "workflow declares least-privilege permissions" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WF'))
perms = doc['permissions']
assert perms['contents'] == 'read'
"
  [ "$status" -eq 0 ]
}

@test "actionlint passes on the workflow" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
