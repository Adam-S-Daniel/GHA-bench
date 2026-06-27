#!/usr/bin/env bats
#
# Workflow STRUCTURE tests (fast, no act). They assert the YAML is well formed,
# declares the expected triggers/jobs/steps, references files that actually
# exist, and passes actionlint.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WF="${ROOT}/.github/workflows/artifact-cleanup-script.yml"
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "workflow passes actionlint cleanly" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares the expected trigger events" {
  for ev in push pull_request schedule workflow_dispatch; do
    run grep -E "^[[:space:]]+${ev}:" "$WF"
    [ "$status" -eq 0 ]
  done
}

@test "workflow defines validate, test and plan jobs" {
  for job in "validate:" "test:" "plan:"; do
    run grep -E "^[[:space:]]+${job}" "$WF"
    [ "$status" -eq 0 ]
  done
}

@test "workflow declares job dependencies via needs" {
  run grep -E "needs:[[:space:]]*validate" "$WF"
  [ "$status" -eq 0 ]
  run grep -E "needs:[[:space:]]*test" "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares least-privilege permissions" {
  run grep -E "permissions:" "$WF"
  [ "$status" -eq 0 ]
  run grep -E "contents:[[:space:]]*read" "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow uses actions/checkout@v4" {
  run grep -E "uses:[[:space:]]*actions/checkout@v4" "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow references files that exist in the repo" {
  # The plan job runs artifact-cleanup.sh against the fixtures.
  grep -q "artifact-cleanup.sh" "$WF"
  [ -f "${ROOT}/artifact-cleanup.sh" ]
  grep -q "tests/cleanup.bats" "$WF"
  [ -f "${ROOT}/tests/cleanup.bats" ]
  grep -q "fixtures/artifacts.tsv" "$WF"
  [ -f "${ROOT}/fixtures/artifacts.tsv" ]
}
