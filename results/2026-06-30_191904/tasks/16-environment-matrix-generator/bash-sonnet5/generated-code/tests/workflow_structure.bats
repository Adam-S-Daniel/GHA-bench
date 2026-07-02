#!/usr/bin/env bats
# Structure/meta tests for the GitHub Actions workflow file itself. These run
# directly on the host (not through `act`) because they need host tooling --
# actionlint, python3+PyYAML -- to inspect the workflow definition and its
# references. The functional behavior of matrix-generator.sh is exercised
# entirely through `act` instead (see tests/matrix_generator.bats, which the
# workflow's lint-and-test job runs inside the container).

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/environment-matrix-generator.yml"
}

# yaml_to_json <path>: convert a YAML file to compact JSON on stdout via
# PyYAML so the rest of the suite can query it with jq.
yaml_to_json() {
  python3 -c 'import yaml, json, sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$1"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow YAML parses without error" {
  run yaml_to_json "$WORKFLOW"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "workflow declares push, pull_request, workflow_dispatch, and schedule triggers" {
  json=$(yaml_to_json "$WORKFLOW")
  # YAML parses the bare key `on:` as boolean key `true` in some PyYAML
  # versions -- handle both `on` and `true` as the trigger map's key.
  triggers=$(echo "$json" | jq -c '.on // .true')
  echo "$triggers" | jq -e 'has("push")' >/dev/null
  echo "$triggers" | jq -e 'has("pull_request")' >/dev/null
  echo "$triggers" | jq -e 'has("workflow_dispatch")' >/dev/null
  echo "$triggers" | jq -e 'has("schedule")' >/dev/null
}

@test "workflow defines the expected jobs with correct needs dependencies" {
  json=$(yaml_to_json "$WORKFLOW")
  jobs=$(echo "$json" | jq -c '.jobs | keys | sort')
  [ "$jobs" = '["build","generate-matrix","lint-and-test"]' ]

  needs_generate=$(echo "$json" | jq -r '.jobs["generate-matrix"].needs')
  [ "$needs_generate" = "lint-and-test" ]

  needs_build=$(echo "$json" | jq -r '.jobs["build"].needs')
  [ "$needs_build" = "generate-matrix" ]
}

@test "workflow declares top-level permissions" {
  json=$(yaml_to_json "$WORKFLOW")
  perms=$(echo "$json" | jq -c '.permissions')
  [ "$perms" != "null" ]
}

@test "lint-and-test job references matrix-generator.sh's real test suite and the script exists on disk" {
  json=$(yaml_to_json "$WORKFLOW")
  run_steps=$(echo "$json" | jq -r '.jobs["lint-and-test"].steps[].run // empty')
  [[ "$run_steps" == *"shellcheck matrix-generator.sh"* ]]
  [[ "$run_steps" == *"bats tests/matrix_generator.bats"* ]]

  [ -f "$PROJECT_ROOT/matrix-generator.sh" ]
  [ -x "$PROJECT_ROOT/matrix-generator.sh" ]
  [ -f "$PROJECT_ROOT/tests/matrix_generator.bats" ]
}

@test "generate-matrix job references a config file that exists on disk" {
  [ -f "$PROJECT_ROOT/fixtures/ci-example.json" ]
  json=$(yaml_to_json "$WORKFLOW")
  default_config=$(echo "$json" | jq -r '.env.DEFAULT_CONFIG')
  [ "$default_config" = "fixtures/ci-example.json" ]
  [ -f "$PROJECT_ROOT/$default_config" ]
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
