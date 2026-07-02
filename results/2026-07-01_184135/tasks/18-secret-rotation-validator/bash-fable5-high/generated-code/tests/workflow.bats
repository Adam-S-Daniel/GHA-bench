#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow.
#
# Written (failing) before the workflow file itself, per TDD. They parse the
# YAML with Python, assert the expected triggers/jobs/steps, verify that every
# repo file the workflow references actually exists, and assert actionlint
# passes with exit code 0.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/secret-rotation-validator.yml"
}

# Small helper: run a Python expression against the parsed workflow document.
# The parsed dict is available as `wf`. PyYAML parses the bare `on:` key as
# boolean True, so triggers live under wf[True].
yq_py() {
  python3 -c "
import sys, yaml
wf = yaml.safe_load(open('$WORKFLOW'))
triggers = wf.get('on', wf.get(True, {}))
print($1)
"
}

@test "workflow file exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))"
  [ "$status" -eq 0 ]
}

@test "workflow has push, pull_request, schedule and workflow_dispatch triggers" {
  run yq_py "sorted(triggers.keys())"
  [ "$status" -eq 0 ]
  [ "$output" = "['pull_request', 'push', 'schedule', 'workflow_dispatch']" ]
}

@test "workflow declares least-privilege permissions" {
  run yq_py "wf['permissions']"
  [ "$output" = "{'contents': 'read'}" ]
}

@test "workflow has test and report jobs, with report depending on test" {
  run yq_py "sorted(wf['jobs'].keys())"
  [ "$output" = "['report', 'test']" ]
  run yq_py "wf['jobs']['report']['needs']"
  [ "$output" = "test" ]
}

@test "both jobs check out the repository with actions/checkout@v4" {
  run yq_py "all(any(s.get('uses','').startswith('actions/checkout@v4') for s in wf['jobs'][j]['steps']) for j in wf['jobs'])"
  [ "$output" = "True" ]
}

@test "test job runs the bats suite" {
  run yq_py "any('bats tests' in s.get('run','') for s in wf['jobs']['test']['steps'])"
  [ "$output" = "True" ]
}

@test "report job invokes the validator script in both formats" {
  run yq_py "any('secret-rotation-validator.sh' in s.get('run','') and '--format markdown' in s.get('run','') for s in wf['jobs']['report']['steps'])"
  [ "$output" = "True" ]
  run yq_py "any('secret-rotation-validator.sh' in s.get('run','') and '--format json' in s.get('run','') for s in wf['jobs']['report']['steps'])"
  [ "$output" = "True" ]
}

@test "every repo file referenced by the workflow exists" {
  # Files the workflow depends on must exist at the paths it uses.
  for f in secret-rotation-validator.sh tests/secret-rotation-validator.bats \
           tests/workflow.bats config/secrets.json; do
    [ -e "$PROJECT_ROOT/$f" ]
  done
  # And the workflow actually references the script and config paths.
  grep -q './secret-rotation-validator.sh' "$WORKFLOW"
  grep -q 'config/secrets.json' "$WORKFLOW"
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
