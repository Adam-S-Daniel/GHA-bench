#!/usr/bin/env bats
# Static structure checks for the GitHub Actions workflow. These do not
# invoke `act` -- they parse the YAML and confirm the pieces required by
# the task are present and correctly wired.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  WORKFLOW="$ROOT/.github/workflows/pr-label-assigner.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow is valid YAML (parseable)" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
# YAML parses bare 'on:' key as boolean True in some parsers; handle both.
triggers = doc.get('on', doc.get(True))
assert 'push' in triggers, 'missing push trigger'
assert 'pull_request' in triggers, 'missing pull_request trigger'
assert 'workflow_dispatch' in triggers, 'missing workflow_dispatch trigger'
"
  [ "$status" -eq 0 ]
}

@test "workflow defines a test job and an assign-labels job with a dependency" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
jobs = doc['jobs']
assert 'test' in jobs, 'missing test job'
assert 'assign-labels' in jobs, 'missing assign-labels job'
needs = jobs['assign-labels'].get('needs')
assert needs == 'test' or needs == ['test'], 'assign-labels must depend on test job'
"
  [ "$status" -eq 0 ]
}

@test "workflow declares read-only top-level permissions" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
assert doc.get('permissions', {}).get('contents') == 'read'
"
  [ "$status" -eq 0 ]
}

@test "workflow references the label-assigner script at a path that exists" {
  run grep -o 'scripts/pr-label-assigner\.sh' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/scripts/pr-label-assigner.sh" ]
}

@test "workflow references the bats test file at a path that exists" {
  run grep -o 'tests/pr_label_assigner\.bats' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/tests/pr_label_assigner.bats" ]
}

@test "workflow references all mocked fixture files and they exist on disk" {
  for f in changed_files_basic.txt changed_files_conflict.txt changed_files_nomatch.txt changed_files_empty.txt rules.conf; do
    run grep -q "fixtures/$f" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ -f "$ROOT/fixtures/$f" ]
  done
}

@test "actionlint passes on the workflow" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
