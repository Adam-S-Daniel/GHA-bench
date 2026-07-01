"""Structural tests for the GitHub Actions workflow file itself."""
import os
import subprocess
import shutil

import yaml

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..")
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "test-results-aggregator.yml")


def _load_workflow():
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert os.path.exists(WORKFLOW_PATH)


def test_workflow_has_expected_triggers():
    wf = _load_workflow()
    # YAML parses the bare key "on" as boolean True
    triggers = wf.get("on") or wf.get(True)
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_expected_jobs_and_dependency():
    wf = _load_workflow()
    jobs = wf["jobs"]
    assert "unit-tests" in jobs
    assert "aggregate-results" in jobs
    assert jobs["aggregate-results"]["needs"] == "unit-tests"


def test_workflow_references_existing_script_and_fixtures():
    wf = _load_workflow()
    steps = wf["jobs"]["aggregate-results"]["steps"]
    run_step = next(s for s in steps if s.get("name") == "Run aggregator on fixture data")
    script_run = run_step["run"]
    assert "aggregator.py" in script_run
    assert os.path.exists(os.path.join(REPO_ROOT, "aggregator.py"))
    for fixture in ["fixtures/junit/run1.xml", "fixtures/junit/run2.xml", "fixtures/json/run3.json"]:
        assert fixture in script_run
        assert os.path.exists(os.path.join(REPO_ROOT, fixture))


def test_actionlint_passes_on_workflow():
    actionlint = shutil.which("actionlint")
    assert actionlint is not None, "actionlint must be installed"
    result = subprocess.run(
        [actionlint, WORKFLOW_PATH], capture_output=True, text=True
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
