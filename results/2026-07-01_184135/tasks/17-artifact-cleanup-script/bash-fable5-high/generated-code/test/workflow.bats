#!/usr/bin/env bats
#
# Workflow structure tests — validate .github/workflows/artifact-cleanup-script.yml
# without needing Docker: YAML structure, script references, and actionlint.
# (Functional testing of the workflow happens through `act` via run-act-tests.sh.)

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  WF="$ROOT/.github/workflows/artifact-cleanup-script.yml"
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares the expected triggers" {
  # push + pull_request for CI, schedule for real cleanup cadence,
  # workflow_dispatch for manual runs.
  grep -Eq '^\s+push:' "$WF"
  grep -Eq '^\s+pull_request:' "$WF"
  grep -Eq '^\s+schedule:' "$WF"
  grep -Eq '^\s+workflow_dispatch:' "$WF"
}

@test "workflow defines lint and test jobs with a dependency between them" {
  grep -Eq '^  lint:' "$WF"
  grep -Eq '^  test:' "$WF"
  grep -Eq '^\s+needs: lint' "$WF"
}

@test "workflow restricts permissions to contents: read" {
  grep -Eq '^permissions:' "$WF"
  grep -Eq '^\s+contents: read' "$WF"
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'uses: actions/checkout@v4' "$WF"
}

@test "every file path the workflow references exists in the repo" {
  # Pull ./-prefixed paths and known repo files out of run: lines.
  for p in artifact-cleanup.sh test/artifact_cleanup.bats \
           test/fixtures/age.tsv test/fixtures/keepn.tsv \
           test/fixtures/size.tsv test/fixtures/combined.tsv; do
    grep -q "$p" "$WF"   # workflow mentions it
    [ -e "$ROOT/$p" ]    # and it exists on disk
  done
}
