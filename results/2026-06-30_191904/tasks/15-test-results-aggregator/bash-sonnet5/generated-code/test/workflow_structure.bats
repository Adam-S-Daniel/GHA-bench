#!/usr/bin/env bats
# Structural tests for the GitHub Actions workflow: YAML shape, that it
# references real files in this repo, and that actionlint is clean.
# These inspect the *workflow definition*, not the aggregator's runtime
# behavior -- functional behavior is only ever exercised through act
# (see test/act_pipeline.bats), per project testing policy.

WORKFLOW="${BATS_TEST_DIRNAME}/../.github/workflows/test-results-aggregator.yml"

setup() {
  cd "${BATS_TEST_DIRNAME}/.." || exit 1
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow YAML is parseable" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request and workflow_dispatch triggers" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
# YAML 1.1 parses bare `on:` as boolean True key; normalize.
triggers = doc.get("on", doc.get(True))
assert "push" in triggers, "missing push trigger"
assert "pull_request" in triggers, "missing pull_request trigger"
assert "workflow_dispatch" in triggers, "missing workflow_dispatch trigger"
PY
  [ "$status" -eq 0 ]
}

@test "workflow defines the aggregate job with checkout as first step" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
jobs = doc["jobs"]
assert "aggregate" in jobs, f"expected job 'aggregate', got {list(jobs)}"
steps = jobs["aggregate"]["steps"]
assert len(steps) > 0
assert steps[0]["uses"].startswith("actions/checkout@"), steps[0]
PY
  [ "$status" -eq 0 ]
}

@test "workflow sets read-only top-level permissions" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
perms = doc.get("permissions")
assert perms is not None, "no permissions block"
assert perms.get("contents") == "read", perms
PY
  [ "$status" -eq 0 ]
}

@test "workflow references aggregate-results.sh which exists in the repo" {
  run grep -c 'aggregate-results.sh' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -x "${BATS_TEST_DIRNAME}/../aggregate-results.sh" ]
}

@test "every fixture path referenced in the workflow exists on disk" {
  run python3 - "$WORKFLOW" <<'PY'
import os, re, sys, yaml
text = open(sys.argv[1]).read()
doc = yaml.safe_load(text)
fixtures_dir = doc["env"]["FIXTURES_DIR"]
# Fixture references may appear as a literal "fixtures/..." path or as
# a shell interpolation of the env var, e.g. "${FIXTURES_DIR}/....xml".
raw = re.findall(r'fixtures/[A-Za-z0-9_.\-]+', text)
interpolated = re.findall(r'\$\{FIXTURES_DIR\}/([A-Za-z0-9_.\-]+)', text)
paths = set(raw) | {f"{fixtures_dir}/{name}" for name in interpolated}
assert paths, "no fixtures/ paths found in workflow"
missing = [p for p in paths if not os.path.exists(p)]
assert not missing, f"missing fixture paths referenced by workflow: {missing}"
PY
  [ "$status" -eq 0 ]
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
