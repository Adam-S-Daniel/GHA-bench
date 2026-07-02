#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow: triggers, jobs, steps,
# script references, and actionlint validation.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(dirname "$TEST_DIR")"
  WORKFLOW="$PROJECT_DIR/.github/workflows/semantic-version-bumper.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow triggers on push and workflow_dispatch" {
  grep -qE '^on:' "$WORKFLOW"
  grep -qE '^  push:' "$WORKFLOW"
  grep -qE '^  workflow_dispatch:' "$WORKFLOW"
}

@test "workflow defines the version-bump job with steps" {
  grep -qE '^jobs:' "$WORKFLOW"
  grep -qE '^  version-bump:' "$WORKFLOW"
  grep -qE '^    steps:' "$WORKFLOW"
  grep -q 'runs-on: ubuntu-latest' "$WORKFLOW"
}

@test "workflow sets explicit permissions" {
  grep -qE '^permissions:' "$WORKFLOW"
  grep -q 'contents: read' "$WORKFLOW"
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'uses: actions/checkout@v4' "$WORKFLOW"
}

@test "workflow references script and test files that exist" {
  grep -q 'bump-version.sh' "$WORKFLOW"
  [ -x "$PROJECT_DIR/bump-version.sh" ]
  grep -q 'tests/bump-version.bats' "$WORKFLOW"
  [ -f "$PROJECT_DIR/tests/bump-version.bats" ]
}

@test "workflow passes actionlint" {
  if ! command -v actionlint >/dev/null 2>&1; then
    skip "actionlint not installed in this environment"
  fi
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}
