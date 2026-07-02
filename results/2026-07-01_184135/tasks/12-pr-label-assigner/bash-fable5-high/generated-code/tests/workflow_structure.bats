#!/usr/bin/env bats
# Structure tests for .github/workflows/pr-label-assigner.yml.
# These run on the host (they need actionlint and python3+PyYAML), not
# inside the act container.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  WF="$ROOT/.github/workflows/pr-label-assigner.yml"
}

# Query the parsed workflow with a python expression over `wf`.
# PyYAML (YAML 1.1) parses the `on:` key as boolean True, hence the alias.
wf_query() {
  python3 -c "
import sys, yaml
with open('$WF') as fh:
    wf = yaml.safe_load(fh)
wf['on'] = wf.get('on', wf.get(True))
print($1)
"
}

@test "workflow file exists and is valid YAML" {
  [ -f "$WF" ]
  run wf_query "type(wf).__name__"
  [ "$status" -eq 0 ]
  [ "$output" = "dict" ]
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow triggers on push, pull_request and workflow_dispatch" {
  run wf_query "sorted(wf['on'])"
  [ "$status" -eq 0 ]
  [ "$output" = "['pull_request', 'push', 'workflow_dispatch']" ]
}

@test "workflow defines test and assign-labels jobs" {
  run wf_query "sorted(wf['jobs'])"
  [ "$status" -eq 0 ]
  [ "$output" = "['assign-labels', 'test']" ]
}

@test "assign-labels depends on the test job" {
  run wf_query "wf['jobs']['assign-labels']['needs']"
  [ "$status" -eq 0 ]
  [ "$output" = "test" ]
}

@test "both jobs check out the repository with actions/checkout@v4" {
  run wf_query "all(any(s.get('uses') == 'actions/checkout@v4' for s in j['steps']) for j in wf['jobs'].values())"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "test job runs the bats suite" {
  run wf_query "any('bats tests/label_assigner.bats' in (s.get('run') or '') for s in wf['jobs']['test']['steps'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "assign-labels job runs label-assigner.sh" {
  run wf_query "any('./label-assigner.sh' in (s.get('run') or '') for s in wf['jobs']['assign-labels']['steps'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "workflow restricts permissions" {
  run wf_query "wf['permissions']['contents']"
  [ "$status" -eq 0 ]
  [ "$output" = "read" ]
}

@test "all paths referenced by the workflow exist in the repo" {
  # script referenced by the assign-labels job
  [ -x "$ROOT/label-assigner.sh" ]
  # bats suite referenced by the test job
  [ -f "$ROOT/tests/label_assigner.bats" ]
  # fixture files referenced via env vars
  run wf_query "wf['env']['RULES_FILE']"
  [ -f "$ROOT/$output" ]
  run wf_query "wf['env']['CHANGED_FILES_FILE']"
  [ -f "$ROOT/$output" ]
}
