#!/usr/bin/env bats
# Structural checks for the GitHub Actions workflow itself: valid YAML,
# expected triggers/jobs, correct references to script files, and a clean
# actionlint run.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORKFLOW="${REPO_ROOT}/.github/workflows/semantic-version-bumper.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow is parseable YAML" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow defines push, pull_request, workflow_dispatch and schedule triggers" {
  grep -q "^on:" "$WORKFLOW"
  grep -q "push:" "$WORKFLOW"
  grep -q "pull_request:" "$WORKFLOW"
  grep -q "workflow_dispatch:" "$WORKFLOW"
  grep -q "schedule:" "$WORKFLOW"
}

@test "workflow defines a test job and a bump job with a needs dependency" {
  grep -q "^  test:" "$WORKFLOW"
  grep -q "^  bump:" "$WORKFLOW"
  grep -q "needs: test" "$WORKFLOW"
}

@test "workflow references the real bump-version.sh script" {
  grep -q "scripts/bump-version.sh" "$WORKFLOW"
  [ -f "${REPO_ROOT}/scripts/bump-version.sh" ]
}

@test "workflow references the real bats test suite" {
  grep -q "tests/bump_version.bats" "$WORKFLOW"
  [ -f "${REPO_ROOT}/tests/bump_version.bats" ]
}

@test "workflow declares least-privilege read-only permissions" {
  grep -q "permissions:" "$WORKFLOW"
  grep -q "contents: read" "$WORKFLOW"
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
