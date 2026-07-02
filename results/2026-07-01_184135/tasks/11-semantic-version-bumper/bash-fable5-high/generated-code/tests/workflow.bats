#!/usr/bin/env bats
# =============================================================================
# Structure tests for .github/workflows/semantic-version-bumper.yml.
#
# Three layers of validation:
#   1. actionlint       — full workflow linting (skipped where not installed,
#                         e.g. inside the act container).
#   2. YAML parsing     — python3 + PyYAML asserts triggers/jobs/steps
#                         structure (skipped where PyYAML is unavailable).
#   3. Path/reference   — plain bash checks that every file the workflow
#                         references actually exists in the repo.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/semantic-version-bumper.yml"
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "actionlint passes with exit code 0" {
  command -v actionlint >/dev/null 2>&1 || skip "actionlint not installed"
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "YAML structure: triggers, jobs, steps and job dependency" {
  python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not available"
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
# PyYAML parses the bare key `on:` as boolean True.
triggers = wf.get("on", wf.get(True))
assert "push" in triggers, "missing push trigger"
assert "workflow_dispatch" in triggers, "missing workflow_dispatch trigger"
assert wf["permissions"] == {"contents": "read"}, "unexpected permissions"
jobs = wf["jobs"]
assert set(jobs) == {"unit-tests", "bump-version"}, f"unexpected jobs: {set(jobs)}"
assert jobs["bump-version"]["needs"] == "unit-tests", "bump-version must depend on unit-tests"
for name, job in jobs.items():
    assert job["runs-on"] == "ubuntu-latest", f"{name}: unexpected runner"
    steps = job["steps"]
    assert steps[0]["uses"].startswith("actions/checkout@v4"), f"{name}: first step must be checkout"
    assert any("run" in s for s in steps), f"{name}: no run steps"
# The bats suite and the bumper script must both be exercised.
unit_runs = " ".join(s.get("run", "") for s in jobs["unit-tests"]["steps"])
assert "bats tests" in unit_runs, "unit-tests job does not run bats"
bump_runs = " ".join(s.get("run", "") for s in jobs["bump-version"]["steps"])
assert "./bump_version.sh" in bump_runs, "bump-version job does not run the script"
print("STRUCTURE-OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"STRUCTURE-OK"* ]]
}

@test "workflow references paths that exist in the repo" {
  # Every file/dir the workflow relies on must be present.
  [ -x "$REPO_ROOT/bump_version.sh" ]
  [ -d "$REPO_ROOT/tests" ]
  [ -d "$REPO_ROOT/ci-fixture" ]
  [ -f "$REPO_ROOT/ci-fixture/commits.txt" ]
  [ -f "$REPO_ROOT/ci-fixture/expected_version.txt" ]
  [ -f "$REPO_ROOT/ci-fixture/case_name.txt" ]
  # The fixture must provide exactly one version source.
  [ -f "$REPO_ROOT/ci-fixture/VERSION" ] || [ -f "$REPO_ROOT/ci-fixture/package.json" ]
  # And the workflow text must actually mention the script and test dir.
  grep -q 'bump_version\.sh' "$WORKFLOW"
  grep -q 'bats tests' "$WORKFLOW"
  grep -q 'FIXTURE_DIR: ci-fixture' "$WORKFLOW"
}
