#!/usr/bin/env bats
#
# Structural tests for the GitHub Actions workflow. These do NOT run act; they
# statically verify the workflow's shape, that it references real files, and
# that it passes actionlint. Fast and dependency-light.

setup() {
  TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  REPO_ROOT="$( cd "$TEST_DIR/.." >/dev/null 2>&1 && pwd )"
  WF="$REPO_ROOT/.github/workflows/semantic-version-bumper.yml"
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "actionlint passes on the workflow (exit 0)" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares the expected trigger events" {
  grep -qE '^[[:space:]]*push:' "$WF"
  grep -qE '^[[:space:]]*pull_request:' "$WF"
  grep -qE '^[[:space:]]*schedule:' "$WF"
  grep -qE '^[[:space:]]*workflow_dispatch:' "$WF"
}

@test "workflow defines validate and bump jobs with a dependency" {
  grep -qE '^[[:space:]]+validate:' "$WF"
  grep -qE '^[[:space:]]+bump:' "$WF"
  grep -qE 'needs:[[:space:]]*validate' "$WF"
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'actions/checkout@v4' "$WF"
}

@test "workflow declares permissions" {
  grep -qE '^permissions:' "$WF"
}

@test "workflow references the bump-version.sh script and the script exists" {
  grep -q 'bump-version.sh' "$WF"
  [ -f "$REPO_ROOT/bump-version.sh" ]
}

@test "workflow prints a NEW_VERSION marker for output capture" {
  grep -q 'NEW_VERSION=' "$WF"
}
