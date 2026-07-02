#!/usr/bin/env bats
# Workflow structure tests: verify the GitHub Actions workflow has the
# expected triggers/jobs/steps, references script files that actually exist,
# and passes actionlint. These run inside the pipeline too (the actionlint
# check auto-skips where the binary is unavailable, e.g. in the act
# container; the harness asserts it separately on the host).

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WF="$ROOT/.github/workflows/artifact-cleanup-script.yml"
}

@test "workflow file exists and is valid YAML" {
  [ -f "$WF" ]
  # python3 + PyYAML if available, otherwise fall back to actionlint's parse
  if python3 -c 'import yaml' 2>/dev/null; then
    run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WF"
    [ "$status" -eq 0 ]
  elif command -v actionlint >/dev/null 2>&1; then
    run actionlint "$WF"
    [ "$status" -eq 0 ]
  else
    skip "no YAML parser available"
  fi
}

@test "workflow declares the expected triggers" {
  grep -q '^on:' "$WF"
  grep -q '^  push:' "$WF"
  grep -q '^  pull_request:' "$WF"
  grep -q '^  workflow_dispatch:' "$WF"
  grep -q '^  schedule:' "$WF"
  grep -q "cron: '0 3 \* \* 1'" "$WF"
}

@test "workflow defines test and cleanup-plan jobs with a dependency" {
  grep -q '^  test:' "$WF"
  grep -q '^  cleanup-plan:' "$WF"
  grep -q '^    needs: test' "$WF"
}

@test "workflow restricts permissions and uses checkout v4" {
  grep -q '^permissions:' "$WF"
  grep -q '^  contents: read' "$WF"
  grep -q 'uses: actions/checkout@v4' "$WF"
}

@test "scripts referenced by the workflow exist and are executable" {
  grep -q 'bats tests/artifact_cleanup.bats' "$WF"
  grep -q 'bash ci/run-cleanup.sh' "$WF"
  [ -x "$ROOT/artifact-cleanup.sh" ]
  [ -x "$ROOT/ci/run-cleanup.sh" ]
  [ -f "$ROOT/tests/artifact_cleanup.bats" ]
  [ -f "$ROOT/ci-fixtures/artifacts.tsv" ]
  [ -f "$ROOT/ci-fixtures/policy.env" ]
}

@test "actionlint passes on the workflow" {
  command -v actionlint >/dev/null 2>&1 || skip "actionlint not installed here"
  run actionlint "$WF"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
