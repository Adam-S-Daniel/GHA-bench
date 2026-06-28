#!/usr/bin/env bats
#
# workflow.bats -- static structure tests for the GitHub Actions workflow.
# These parse the YAML and assert on triggers, jobs, steps, script references,
# and that actionlint passes. Fast (no Docker / act required).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WF="$ROOT/.github/workflows/environment-matrix-generator.yml"
}

# Tiny helper: query the parsed workflow with a python expression over `wf`.
y() {
  python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
print(eval(sys.argv[2]))
' "$WF" "$1"
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow has the expected trigger events" {
  # PyYAML parses the `on:` key as Python boolean True.
  run y "sorted(wf[True].keys())"
  [ "$status" -eq 0 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"pull_request"* ]]
  [[ "$output" == *"workflow_dispatch"* ]]
  [[ "$output" == *"schedule"* ]]
}

@test "workflow declares least-privilege permissions" {
  run y "wf['permissions']['contents']"
  [ "$status" -eq 0 ]
  [ "$output" = "read" ]
}

@test "workflow defines both jobs with a dependency" {
  run y "sorted(wf['jobs'].keys())"
  [[ "$output" == *"generate-matrix"* ]]
  [[ "$output" == *"summary"* ]]
  run y "wf['jobs']['summary']['needs']"
  [[ "$output" == *"generate-matrix"* ]]
}

@test "generate-matrix job checks out and runs the case harness" {
  run y "[s.get('uses','') for s in wf['jobs']['generate-matrix']['steps']]"
  [[ "$output" == *"actions/checkout@v4"* ]]
  run y "' '.join(s.get('run','') for s in wf['jobs']['generate-matrix']['steps'])"
  [[ "$output" == *"run-cases.sh"* ]]
  [[ "$output" == *"generate-matrix.sh"* ]] || [[ "$output" == *'$GENERATOR'* ]]
}

@test "referenced script paths exist in the repo" {
  [ -f "$ROOT/generate-matrix.sh" ]
  [ -f "$ROOT/matrix.jq" ]
  [ -f "$ROOT/tests/run-cases.sh" ]
  [ -f "$ROOT/tests/expected.json" ]
}

@test "workflow env points at the generator and a real config" {
  run y "wf['env']['GENERATOR']"
  [[ "$output" == *"generate-matrix.sh"* ]]
  cfg="$(y "wf['env']['CONFIG']")"
  [ -f "$ROOT/$cfg" ]
}
