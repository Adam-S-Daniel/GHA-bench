#!/usr/bin/env bats
# Workflow structure tests: verify .github/workflows/pr-label-assigner.yml
# has the expected triggers/jobs/steps, references files that actually
# exist, and passes actionlint.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  WORKFLOW="$ROOT/.github/workflows/pr-label-assigner.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
  grep -qE '^on:' "$WORKFLOW"
  grep -qE '^  push:' "$WORKFLOW"
  grep -qE '^  pull_request:' "$WORKFLOW"
  grep -qE '^  workflow_dispatch:' "$WORKFLOW"
}

@test "workflow defines the 'label' job on ubuntu-latest" {
  grep -qE '^jobs:' "$WORKFLOW"
  grep -qE '^  label:' "$WORKFLOW"
  grep -qE 'runs-on: ubuntu-latest' "$WORKFLOW"
}

@test "workflow declares least-privilege permissions" {
  grep -qE '^permissions:' "$WORKFLOW"
  grep -qE '^  contents: read' "$WORKFLOW"
}

@test "workflow uses actions/checkout@v4 and runs the bats suite" {
  grep -qF 'uses: actions/checkout@v4' "$WORKFLOW"
  grep -qF 'bats test/' "$WORKFLOW"
}

@test "workflow references label-assigner.sh and the path exists" {
  grep -qF 'label-assigner.sh' "$WORKFLOW"
  [ -f "$ROOT/label-assigner.sh" ]
}

@test "files referenced by workflow env exist" {
  # env: RULES_FILE / CHANGED_FILES point at real repo paths
  grep -qF 'RULES_FILE: ci/labels.rules' "$WORKFLOW"
  grep -qF 'CHANGED_FILES: ci/changed-files.txt' "$WORKFLOW"
  [ -f "$ROOT/ci/labels.rules" ]
  [ -f "$ROOT/ci/changed-files.txt" ]
}

@test "actionlint passes with exit code 0" {
  if ! command -v actionlint >/dev/null 2>&1; then
    skip "actionlint not installed in this environment"
  fi
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}
