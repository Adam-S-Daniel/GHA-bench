#!/usr/bin/env bats
# Structural tests for the GitHub Actions workflow.
# They verify the workflow parses (via actionlint, which fully parses the
# YAML), declares the expected triggers/jobs/steps, and that every file the
# workflow references actually exists in the repository.

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/environment-matrix-generator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "actionlint passes (valid YAML and action references)" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
  run grep -E '^(on|"on"):' "$WORKFLOW"
  [ "$status" -eq 0 ]
  grep -qE '^[[:space:]]+push:' "$WORKFLOW"
  grep -qE '^[[:space:]]+pull_request:' "$WORKFLOW"
  grep -qE '^[[:space:]]+workflow_dispatch:' "$WORKFLOW"
}

@test "workflow defines the expected jobs" {
  grep -qE '^[[:space:]]{2}test:' "$WORKFLOW"
  grep -qE '^[[:space:]]{2}generate-matrix:' "$WORKFLOW"
  grep -qE '^[[:space:]]{2}use-matrix:' "$WORKFLOW"
}

@test "workflow restricts permissions and uses checkout@v4" {
  grep -qE '^permissions:' "$WORKFLOW"
  grep -q 'contents: read' "$WORKFLOW"
  grep -q 'actions/checkout@v4' "$WORKFLOW"
}

@test "downstream jobs declare dependencies with needs" {
  grep -qE 'needs:[[:space:]]*test' "$WORKFLOW"
  grep -qE 'needs:[[:space:]]*generate-matrix' "$WORKFLOW"
}

@test "workflow references the generator script and the path exists" {
  grep -q 'matrix_generator.sh' "$WORKFLOW"
  [ -f "$PROJECT_ROOT/matrix_generator.sh" ]
  [ -x "$PROJECT_ROOT/matrix_generator.sh" ]
}

@test "every fixture path referenced by the workflow exists" {
  # Fixtures are referenced as "$FIXTURES/<name>.json" (env FIXTURES=test/fixtures).
  paths="$(grep -oE '(test/fixtures|\$FIXTURES)/[A-Za-z0-9_.-]+\.json' "$WORKFLOW" \
           | sed 's|^\$FIXTURES|test/fixtures|' | sort -u)"
  [ -n "$paths" ]
  while IFS= read -r p; do
    [ -f "$PROJECT_ROOT/$p" ]
  done <<< "$paths"
}
