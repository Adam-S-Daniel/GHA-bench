# Structure tests for the GitHub Actions workflow.
#
# These verify the workflow file itself: valid YAML/actions syntax
# (actionlint), expected triggers/jobs/steps, and that every file the
# workflow references actually exists in the repository.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  WORKFLOW="$ROOT/.github/workflows/environment-matrix-generator.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "actionlint passes with exit code 0" {
  command -v actionlint > /dev/null || skip "actionlint not installed"
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow parses as valid YAML with the expected jobs (via act -l)" {
  command -v act > /dev/null || skip "act not installed"
  # `act -l` fully parses the workflow; it fails on invalid YAML.
  run act push -l -W "$WORKFLOW" --directory "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unit_tests"* ]]
  [[ "$output" == *"generate_matrix"* ]]
  [[ "$output" == *"build"* ]]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
  grep -Eq '^\s+push:' "$WORKFLOW"
  grep -Eq '^\s+pull_request:' "$WORKFLOW"
  grep -Eq '^\s+workflow_dispatch:' "$WORKFLOW"
}

@test "workflow restricts permissions to contents: read" {
  grep -A1 '^permissions:' "$WORKFLOW" | grep -q 'contents: read'
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'uses: actions/checkout@v4' "$WORKFLOW"
}

@test "build job depends on generate_matrix which depends on unit_tests" {
  grep -q 'needs: unit_tests' "$WORKFLOW"
  grep -q 'needs: generate_matrix' "$WORKFLOW"
}

@test "workflow consumes the generated matrix via fromJSON" {
  grep -q 'matrix: ${{ fromJSON(needs.generate_matrix.outputs.matrix) }}' "$WORKFLOW"
}

@test "files referenced by the workflow exist" {
  # The workflow runs ./matrix-gen.sh, bats test/matrix_gen.bats, and
  # reads the default CONFIG_FILE config.json.
  grep -q './matrix-gen.sh' "$WORKFLOW"
  [ -x "$ROOT/matrix-gen.sh" ]
  grep -q 'test/matrix_gen.bats' "$WORKFLOW"
  [ -f "$ROOT/test/matrix_gen.bats" ]
  grep -q "'config.json'" "$WORKFLOW"
  [ -f "$ROOT/config.json" ]
}
