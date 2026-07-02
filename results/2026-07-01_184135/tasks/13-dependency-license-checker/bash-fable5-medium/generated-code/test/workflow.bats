#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow. These verify the
# workflow YAML has the expected triggers, jobs, and steps, that the
# files it references actually exist, and that actionlint accepts it.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(dirname "$TEST_DIR")"
  WORKFLOW="$PROJECT_DIR/.github/workflows/dependency-license-checker.yml"
}

@test "workflow: file exists and is valid YAML (parseable by python or grep-sane)" {
  [ -f "$WORKFLOW" ]
  # Basic YAML sanity: a name and an on: block must be present.
  grep -qE '^name:' "$WORKFLOW"
  grep -qE '^on:' "$WORKFLOW"
}

@test "workflow: has push, pull_request, workflow_dispatch and schedule triggers" {
  grep -qE '^\s+push:' "$WORKFLOW"
  grep -qE '^\s+pull_request:' "$WORKFLOW"
  grep -qE '^\s+workflow_dispatch:' "$WORKFLOW"
  grep -qE '^\s+schedule:' "$WORKFLOW"
}

@test "workflow: defines test and compliance-report jobs with a dependency" {
  grep -qE '^\s+test:' "$WORKFLOW"
  grep -qE '^\s+compliance-report:' "$WORKFLOW"
  grep -qE '^\s+needs: test' "$WORKFLOW"
}

@test "workflow: uses actions/checkout@v4 and restricts permissions" {
  grep -q 'uses: actions/checkout@v4' "$WORKFLOW"
  grep -qE '^permissions:' "$WORKFLOW"
  grep -qE '^\s+contents: read' "$WORKFLOW"
}

@test "workflow: references script and test files that exist" {
  grep -q 'license_checker.sh' "$WORKFLOW"
  grep -q 'bats test/' "$WORKFLOW"
  [ -x "$PROJECT_DIR/license_checker.sh" ]
  [ -d "$PROJECT_DIR/test" ]
  # Fallback fixture paths named in the workflow env must exist too.
  [ -f "$PROJECT_DIR/test/fixtures/package.json" ]
  [ -f "$PROJECT_DIR/test/fixtures/policy.conf" ]
  [ -f "$PROJECT_DIR/test/fixtures/licenses.db" ]
}

@test "workflow: passes actionlint" {
  if ! command -v actionlint >/dev/null 2>&1; then
    skip "actionlint not installed in this environment"
  fi
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}
