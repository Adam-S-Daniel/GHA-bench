#!/usr/bin/env bats
#
# Workflow-structure tests. These run locally (NOT inside the act container):
# they parse the workflow YAML, assert on its triggers/jobs/steps, confirm the
# referenced script paths exist, and verify actionlint passes cleanly.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WF="$ROOT/.github/workflows/secret-rotation-validator.yml"
  cd "$ROOT"
}

wf() { python3 tests-structure/wf.py "$1"; }

@test "workflow file exists and is valid YAML" {
  [ -f "$WF" ]
  run wf name
  [ "$status" -eq 0 ]
  [ "$output" = "Secret Rotation Validator srv18b" ]
}

@test "declares the expected trigger events" {
  run wf triggers
  [ "$status" -eq 0 ]
  [ "$output" = "pull_request,push,schedule,workflow_dispatch" ]
}

@test "uses least-privilege contents: read permission" {
  run wf permissions
  [ "$output" = "read" ]
}

@test "defines both the test and report jobs" {
  run wf jobs
  [ "$output" = "report,test" ]
}

@test "report job depends on the test job" {
  run wf report-needs
  [ "$output" = "test" ]
}

@test "uses actions/checkout@v4" {
  run wf uses-checkout
  [ "$output" = "True" ]
}

@test "references the validator script" {
  run wf runs-script
  [ "$output" = "True" ]
}

@test "runs the bats suite inside the workflow" {
  run wf runs-bats
  [ "$output" = "True" ]
}

@test "referenced script and config paths exist on disk" {
  [ -f "$ROOT/secret-rotation-validator.sh" ]
  config="$(wf config-file)"
  [ -f "$ROOT/$config" ]
  [ -d "$ROOT/tests" ]
}

@test "actionlint passes cleanly (exit 0)" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
