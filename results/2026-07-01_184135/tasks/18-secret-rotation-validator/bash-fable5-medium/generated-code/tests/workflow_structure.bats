#!/usr/bin/env bats
# Structural tests for the GitHub Actions workflow.
# These run on the host (they need actionlint/python3), not through act.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/secret-rotation-validator.yml"
}

# Helper: run a python3 assertion over the parsed workflow YAML.
# PyYAML parses the bare `on:` key as boolean True (YAML 1.1), so the
# snippet exposes it as `triggers`.
yaml_check() {
  python3 - "$WORKFLOW" <<EOF
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
triggers = wf.get('on', wf.get(True))
jobs = wf['jobs']
assert $1, "failed: $1"
EOF
}

@test "workflow file exists and actionlint passes (exit 0)" {
  [ -f "$WORKFLOW" ]
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow declares the expected triggers" {
  yaml_check "set(triggers) == {'push', 'pull_request', 'workflow_dispatch', 'schedule'}"
  yaml_check "triggers['schedule'][0]['cron'] == '0 6 * * 1'"
}

@test "workflow has test and report jobs with correct dependency" {
  yaml_check "set(jobs) == {'test', 'report'}"
  yaml_check "jobs['report']['needs'] == 'test'"
  yaml_check "all(j['runs-on'] == 'ubuntu-latest' for j in jobs.values())"
}

@test "workflow restricts permissions to contents: read" {
  yaml_check "wf['permissions'] == {'contents': 'read'}"
}

@test "workflow uses actions/checkout@v4 in every job" {
  yaml_check "all(any(s.get('uses') == 'actions/checkout@v4' for s in j['steps']) for j in jobs.values())"
}

@test "workflow references script and test files that exist on disk" {
  # Every project path mentioned in run: steps must exist in the repo.
  grep -q 'secret-rotation-validator\.sh' "$WORKFLOW"
  [ -f "$REPO_ROOT/secret-rotation-validator.sh" ]
  grep -q 'tests/secret_rotation_validator\.bats' "$WORKFLOW"
  [ -f "$REPO_ROOT/tests/secret_rotation_validator.bats" ]
  yaml_check "wf['env']['CONFIG_PATH'] == 'fixtures/secrets.json'"
  yaml_check "wf['env']['PARAMS_PATH'] == 'fixtures/params.env'"
  [ -f "$REPO_ROOT/fixtures/secrets.json" ]
  [ -f "$REPO_ROOT/fixtures/params.env" ]
}
