#!/usr/bin/env bats
#
# Workflow STRUCTURE tests (no act). These parse the workflow YAML and assert on
# its expected shape, verify it references the script files that actually exist,
# and confirm actionlint validates it cleanly.

setup() {
  PROJECT_DIR="$( cd "$BATS_TEST_DIRNAME/.." && pwd )"
  WF="$PROJECT_DIR/.github/workflows/dependency-license-checker.yml"
  Q() { python3 "$BATS_TEST_DIRNAME/workflow_structure.py" "$WF" "$1"; }
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "actionlint validates the workflow cleanly (exit 0)" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow declares the expected trigger events" {
  run Q triggers
  [ "$status" -eq 0 ]
  [ "$output" = "pull_request,push,schedule,workflow_dispatch" ]
}

@test "workflow defines the license-check and summary jobs" {
  run Q jobs
  [ "$status" -eq 0 ]
  [ "$output" = "license-check,summary" ]
}

@test "summary job depends on (needs) the license-check job" {
  run Q summary-needs
  [ "$status" -eq 0 ]
  [ "$output" = "license-check" ]
}

@test "workflow checks out the repo with actions/checkout@v4" {
  run Q checkout-ref
  [ "$status" -eq 0 ]
  [ "$output" = "actions/checkout@v4" ]
}

@test "workflow sets least-privilege permissions (contents: read)" {
  run Q permissions
  [ "$status" -eq 0 ]
  [ "$output" = "read" ]
}

@test "workflow defines CONFIG_FILE and DB_FILE environment variables" {
  run Q env-keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFIG_FILE"* ]]
  [[ "$output" == *"DB_FILE"* ]]
}

@test "workflow references the license-checker.sh script" {
  run Q references-script
  [ "$status" -eq 0 ]
  [ "$output" = "yes" ]
}

@test "all files the workflow depends on exist on disk" {
  [ -f "$PROJECT_DIR/license-checker.sh" ]
  [ -f "$PROJECT_DIR/licenses.config" ]
  [ -f "$PROJECT_DIR/license-db.tsv" ]
  [ -f "$PROJECT_DIR/tests/license-checker.bats" ]
  [ -f "$PROJECT_DIR/tests/mocks/mock-lookup.sh" ]
}
