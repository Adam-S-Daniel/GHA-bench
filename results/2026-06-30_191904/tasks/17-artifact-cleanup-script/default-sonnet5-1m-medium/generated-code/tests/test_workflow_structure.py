"""
Structural tests for the GitHub Actions workflow. These check the YAML
shape and file references without needing Docker/act, so they run as part
of the normal `pytest` suite.
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).parent.parent
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "artifact-cleanup-script.yml"


def _load_workflow() -> dict:
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_has_expected_triggers():
    workflow = _load_workflow()
    # YAML parses the bare key "on" as boolean True.
    triggers = workflow.get("on") or workflow.get(True)
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_has_expected_jobs_and_dependency():
    workflow = _load_workflow()
    jobs = workflow["jobs"]
    assert "test" in jobs
    assert "cleanup-plan" in jobs
    assert jobs["cleanup-plan"]["needs"] == "test"


def test_workflow_permissions_are_least_privilege():
    workflow = _load_workflow()
    assert workflow["permissions"] == {"contents": "read"}


def test_workflow_steps_reference_project_files_that_exist():
    workflow = _load_workflow()
    for job in workflow["jobs"].values():
        for step in job["steps"]:
            run = step.get("run", "")
            if "cli.py" in run:
                assert (PROJECT_ROOT / "cli.py").is_file()
            if "pytest tests/" in run:
                assert (PROJECT_ROOT / "tests").is_dir()
    assert (PROJECT_ROOT / "fixtures" / "sample_artifacts.json").is_file()


@pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW_PATH)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
