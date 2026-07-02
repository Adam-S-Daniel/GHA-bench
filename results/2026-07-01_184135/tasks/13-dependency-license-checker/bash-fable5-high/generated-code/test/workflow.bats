#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow. These run on the host
# (they need actionlint and PyYAML), unlike test/license_checker.bats which
# also runs inside the CI container.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROOT_DIR="$(dirname "$TEST_DIR")"
  WORKFLOW="$ROOT_DIR/.github/workflows/dependency-license-checker.yml"
}

# Helper: run a python one-liner with the parsed workflow bound to `wf`.
# PyYAML parses the bare `on:` key as boolean True, so normalize it to "on".
wf_query() {
  python3 - "$WORKFLOW" "$1" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    wf = yaml.safe_load(f)
if True in wf:  # yaml 1.1 parses unquoted `on` as boolean True
    wf["on"] = wf.pop(True)
print(eval(sys.argv[2]))
PY
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow is valid YAML with the expected name" {
  run wf_query "wf['name']"
  [ "$status" -eq 0 ]
  [ "$output" = "Dependency License Checker" ]
}

@test "workflow triggers on push, pull_request, workflow_dispatch and schedule" {
  run wf_query "sorted(wf['on'].keys())"
  [ "$status" -eq 0 ]
  [ "$output" = "['pull_request', 'push', 'schedule', 'workflow_dispatch']" ]
}

@test "workflow defines test and license-check jobs" {
  run wf_query "sorted(wf['jobs'].keys())"
  [ "$status" -eq 0 ]
  [ "$output" = "['license-check', 'test']" ]
}

@test "license-check job depends on the test job" {
  run wf_query "wf['jobs']['license-check']['needs']"
  [ "$status" -eq 0 ]
  [ "$output" = "test" ]
}

@test "workflow restricts permissions to contents: read" {
  run wf_query "wf['permissions']"
  [ "$status" -eq 0 ]
  [ "$output" = "{'contents': 'read'}" ]
}

@test "both jobs check out the repo with actions/checkout@v4" {
  run wf_query "all(j['steps'][0]['uses'] == 'actions/checkout@v4' for j in wf['jobs'].values())"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "workflow references the checker script and the script exists" {
  run wf_query "any('./license-checker.sh' in s.get('run','') for s in wf['jobs']['license-check']['steps'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
  [ -x "$ROOT_DIR/license-checker.sh" ]
}

@test "workflow references the bats suite and the suite exists" {
  run wf_query "any('bats test/license_checker.bats' in s.get('run','') for s in wf['jobs']['test']['steps'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
  [ -f "$ROOT_DIR/test/license_checker.bats" ]
}

@test "default ci-input files referenced by the workflow exist" {
  [ -f "$ROOT_DIR/ci-input/package.json" ]
  [ -f "$ROOT_DIR/ci-input/config.txt" ]
  [ -f "$ROOT_DIR/ci-input/licenses.tsv" ]
}
