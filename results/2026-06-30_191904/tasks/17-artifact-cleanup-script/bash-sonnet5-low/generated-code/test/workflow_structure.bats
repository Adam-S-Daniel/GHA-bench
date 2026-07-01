#!/usr/bin/env bats
#
# Structural checks for the GitHub Actions workflow: triggers, jobs/steps,
# referenced paths existing on disk, and actionlint passing cleanly.

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME}/.."
  WORKFLOW="${REPO_ROOT}/.github/workflows/artifact-cleanup-script.yml"
}

@test "workflow file exists" {
  [ -f "${WORKFLOW}" ]
}

@test "workflow defines push, pull_request, workflow_dispatch and schedule triggers" {
  grep -q '^on:' "${WORKFLOW}"
  grep -q 'push:' "${WORKFLOW}"
  grep -q 'pull_request:' "${WORKFLOW}"
  grep -q 'workflow_dispatch:' "${WORKFLOW}"
  grep -q 'schedule:' "${WORKFLOW}"
}

@test "workflow defines a jobs section with steps" {
  grep -q '^jobs:' "${WORKFLOW}"
  grep -q 'steps:' "${WORKFLOW}"
}

@test "workflow declares minimal read-only permissions" {
  grep -q 'permissions:' "${WORKFLOW}"
  grep -q 'contents: read' "${WORKFLOW}"
}

@test "workflow references scripts/artifact-cleanup.sh which exists on disk" {
  grep -q 'scripts/artifact-cleanup.sh' "${WORKFLOW}"
  [ -f "${REPO_ROOT}/scripts/artifact-cleanup.sh" ]
}

@test "workflow references test/artifact_cleanup.bats which exists on disk" {
  grep -q 'test/artifact_cleanup.bats' "${WORKFLOW}"
  [ -f "${REPO_ROOT}/test/artifact_cleanup.bats" ]
}

@test "all fixtures referenced in workflow exist on disk" {
  for f in age-policy.json size-policy.json keep-latest.json combined.json; do
    grep -q "${f}" "${WORKFLOW}"
    [ -f "${REPO_ROOT}/test/fixtures/${f}" ]
  done
}

# bats test_tags=requires-actionlint
@test "actionlint passes cleanly on the workflow file" {
  run actionlint "${WORKFLOW}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
