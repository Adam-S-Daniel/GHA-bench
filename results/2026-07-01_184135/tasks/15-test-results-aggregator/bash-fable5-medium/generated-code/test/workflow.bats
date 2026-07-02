#!/usr/bin/env bats
# =============================================================================
# Workflow structure tests for .github/workflows/test-results-aggregator.yml
# Verifies triggers, jobs, steps, script references, and actionlint validity.
# (These are also written TDD-style: assertions first, workflow adjusted to
# make them pass.)
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/test-results-aggregator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow has push, pull_request and workflow_dispatch triggers" {
  grep -q '^on:' "$WORKFLOW"
  grep -q '^  push:' "$WORKFLOW"
  grep -q '^  pull_request:' "$WORKFLOW"
  grep -q '^  workflow_dispatch:' "$WORKFLOW"
}

@test "workflow declares least-privilege permissions" {
  grep -q '^permissions:' "$WORKFLOW"
  grep -q 'contents: read' "$WORKFLOW"
}

@test "workflow defines test and aggregate jobs with dependency" {
  grep -q '^  test:' "$WORKFLOW"
  grep -q '^  aggregate:' "$WORKFLOW"
  grep -q 'needs: test' "$WORKFLOW"
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'uses: actions/checkout@v4' "$WORKFLOW"
}

@test "workflow sets the RESULTS_DIR environment variable with a default" {
  grep -q "RESULTS_DIR: \${{ vars.RESULTS_DIR || 'fixtures' }}" "$WORKFLOW"
}

@test "workflow references the aggregator script and it exists" {
  grep -q './aggregate-test-results.sh' "$WORKFLOW"
  [ -x "$PROJECT_ROOT/aggregate-test-results.sh" ]
}

@test "workflow runs the bats test suite and the test files exist" {
  grep -q 'bats test/' "$WORKFLOW"
  [ -f "$PROJECT_ROOT/test/aggregator.bats" ]
  [ -f "$PROJECT_ROOT/test/workflow.bats" ]
}

@test "fixture directories referenced by the workflow exist" {
  [ -f "$PROJECT_ROOT/fixtures/run1.xml" ]
  [ -f "$PROJECT_ROOT/fixtures/run2.xml" ]
  [ -f "$PROJECT_ROOT/fixtures/run3.json" ]
}

@test "actionlint passes on the workflow (exit code 0)" {
  if ! command -v actionlint > /dev/null 2>&1; then
    # Installed on demand inside the CI container by the workflow harness
    skip "actionlint not available on PATH"
  fi
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}
