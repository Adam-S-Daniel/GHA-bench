#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow.
#
# These verify the workflow YAML itself: triggers, jobs, step wiring, that
# every script/path it references actually exists in the repo, and that
# actionlint accepts it.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/test-results-aggregator.yml"
}

# Helper: parse the workflow YAML with python3 and run an assertion snippet.
# PyYAML parses bare `on:` as the boolean key True (YAML 1.1), so the helper
# exposes it as `on_` for convenience.
yaml_query() {
  python3 - "$WORKFLOW" <<PYEOF
import sys, yaml
with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)
on_ = wf.get('on', wf.get(True))
assert $1, "assertion failed: $1"
PYEOF
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow passes actionlint (exit code 0)" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow triggers on push, pull_request and workflow_dispatch" {
  yaml_query "set(on_) >= {'push', 'pull_request', 'workflow_dispatch'}"
}

@test "workflow restricts permissions to contents: read" {
  yaml_query "wf['permissions'] == {'contents': 'read'}"
}

@test "workflow defines bats-tests and aggregate jobs, aggregate needs bats-tests" {
  yaml_query "set(wf['jobs']) == {'bats-tests', 'aggregate'}"
  yaml_query "wf['jobs']['aggregate']['needs'] == 'bats-tests'"
}

@test "workflow jobs use actions/checkout@v4 and run on ubuntu-latest" {
  yaml_query "all(j['runs-on'] == 'ubuntu-latest' for j in wf['jobs'].values())"
  yaml_query "all(any(s.get('uses', '').startswith('actions/checkout@v4') for s in j['steps']) for j in wf['jobs'].values())"
}

@test "workflow runs the bats suite and the aggregator script" {
  yaml_query "any('bats tests/' in s.get('run', '') for s in wf['jobs']['bats-tests']['steps'])"
  yaml_query "any('./aggregate-test-results.sh' in s.get('run', '') for s in wf['jobs']['aggregate']['steps'])"
}

@test "every path the workflow references exists in the repo" {
  # The aggregator script must exist and be executable ...
  [ -x "$REPO_ROOT/aggregate-test-results.sh" ]
  # ... the bats suite directory must exist ...
  [ -d "$REPO_ROOT/tests" ]
  # ... and the fallback fixture set used by the aggregate job must exist.
  [ -d "$REPO_ROOT/fixtures/matrix-flaky" ]
}
