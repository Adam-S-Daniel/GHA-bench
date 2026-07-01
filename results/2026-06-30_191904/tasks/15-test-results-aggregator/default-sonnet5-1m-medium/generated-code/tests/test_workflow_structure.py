"""
Structural tests for the GitHub Actions workflow itself: valid YAML, expected
triggers/jobs/steps, correct script references, and a clean actionlint pass.
"""
import os
import shutil
import subprocess
import sys

import yaml

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "test-results-aggregator.yml")


def _load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        # YAML parses the bare "on:" key as boolean True; PyYAML's loader
        # will surface it as key True unless we re-map it back to "on".
        data = yaml.safe_load(f)
    if True in data:
        data["on"] = data.pop(True)
    return data


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_is_valid_yaml_with_expected_triggers():
    data = _load_workflow()
    assert "on" in data
    triggers = data["on"]
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_expected_jobs_in_order():
    data = _load_workflow()
    jobs = data["jobs"]
    assert set(["unit-tests", "aggregate-matrix-results", "aggregate-summary"]).issubset(jobs.keys())

    # aggregate-matrix-results depends on unit-tests; aggregate-summary depends on that.
    assert jobs["aggregate-matrix-results"]["needs"] == "unit-tests"
    assert jobs["aggregate-summary"]["needs"] == "aggregate-matrix-results"


def test_workflow_declares_read_only_permissions():
    data = _load_workflow()
    assert data["permissions"] == {"contents": "read"}


def test_workflow_references_existing_script_and_fixtures():
    data = _load_workflow()
    jobs = data["jobs"]

    # Collect every run: block's shell text across all jobs/steps.
    all_run_text = ""
    for job in jobs.values():
        for step in job.get("steps", []):
            if "run" in step:
                all_run_text += step["run"] + "\n"

    assert "aggregator.py" in all_run_text
    assert os.path.isfile(os.path.join(REPO_ROOT, "aggregator.py"))

    # Fixture paths referenced directly in run: steps, plus those referenced
    # indirectly via the matrix strategy (matrix.fixture -> upload-artifact path).
    matrix_fixtures = {
        entry["fixture"]
        for job in jobs.values()
        for entry in job.get("strategy", {}).get("matrix", {}).get("include", [])
        if "fixture" in entry
    }

    for fixture in [
        "fixtures/junit_all_pass.xml",
        "fixtures/results_all_pass.json",
        "fixtures/matrix_run_ubuntu.xml",
        "fixtures/matrix_run_macos.json",
    ]:
        assert fixture in all_run_text or fixture in matrix_fixtures
        assert os.path.isfile(os.path.join(REPO_ROOT, fixture))


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        import pytest

        pytest.skip("actionlint not installed in this environment")

    result = subprocess.run(
        [actionlint, WORKFLOW_PATH],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
