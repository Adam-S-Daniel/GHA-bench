#!/usr/bin/env bats

# Test suite for GitHub Actions workflow structure validation

setup() {
  WORKFLOW_FILE="${BATS_TEST_DIRNAME}/../.github/workflows/environment-matrix-generator.yml"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
}

# Test 1: Workflow file exists
@test "workflow file exists" {
  [ -f "$WORKFLOW_FILE" ]
}

# Test 2: Workflow has required trigger events
@test "workflow has push trigger" {
  grep -q "push:" "$WORKFLOW_FILE"
}

@test "workflow has pull_request trigger" {
  grep -q "pull_request:" "$WORKFLOW_FILE"
}

@test "workflow has workflow_dispatch trigger" {
  grep -q "workflow_dispatch:" "$WORKFLOW_FILE"
}

# Test 3: Workflow has required jobs
@test "workflow has test job" {
  grep -q "test:" "$WORKFLOW_FILE"
}

@test "workflow has actionlint job" {
  grep -q "actionlint:" "$WORKFLOW_FILE"
}

# Test 4: Test job has required steps
@test "test job has checkout step" {
  grep -A 50 "^  test:" "$WORKFLOW_FILE" | grep -q "actions/checkout@v4"
}

@test "test job has install dependencies step" {
  grep -A 50 "^  test:" "$WORKFLOW_FILE" | grep -q "Install dependencies"
}

@test "test job has shellcheck step" {
  grep -A 50 "^  test:" "$WORKFLOW_FILE" | grep -q "shellcheck"
}

@test "test job has bats test step" {
  grep -A 50 "^  test:" "$WORKFLOW_FILE" | grep -q "bats"
}

# Test 5: Script file paths exist and are referenced correctly
@test "script file exists at referenced path" {
  grep -o "src/matrix-generator.sh" "$WORKFLOW_FILE"
  [ -f "$SCRIPT_DIR/src/matrix-generator.sh" ]
}

@test "fixtures are referenced in workflow" {
  grep -q "fixtures/" "$WORKFLOW_FILE"
}

# Test 6: Workflow file is valid YAML (can be parsed)
@test "workflow YAML is parseable" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW_FILE'))"
}

# Test 7: Workflow references existing actions
@test "workflow references valid checkout action" {
  grep -q "actions/checkout@v4" "$WORKFLOW_FILE"
}

# Test 8: Actionlint job exists with proper steps
@test "actionlint job has checkout step" {
  grep -A 20 "^  actionlint:" "$WORKFLOW_FILE" | grep -q "actions/checkout@v4"
}

@test "actionlint job validates workflow syntax" {
  grep -A 20 "^  actionlint:" "$WORKFLOW_FILE" | grep -q "actionlint"
}

# Test 9: Permissions are set appropriately
@test "workflow has permissions section" {
  grep -q "permissions:" "$WORKFLOW_FILE"
}

@test "workflow has read permissions" {
  grep -A 2 "permissions:" "$WORKFLOW_FILE" | grep -q "contents: read"
}

# Test 10: Runner is specified
@test "test job specifies runner" {
  grep -A 5 "^  test:" "$WORKFLOW_FILE" | grep -q "runs-on: ubuntu-latest"
}

@test "actionlint job specifies runner" {
  grep -A 5 "^  actionlint:" "$WORKFLOW_FILE" | grep -q "runs-on: ubuntu-latest"
}
