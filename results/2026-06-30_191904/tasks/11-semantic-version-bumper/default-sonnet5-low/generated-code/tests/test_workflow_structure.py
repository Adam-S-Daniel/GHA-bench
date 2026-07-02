"""
Structural tests for the GitHub Actions workflow: valid YAML, expected
triggers/jobs/steps, correct file references, and a clean actionlint pass.
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "semantic-version-bumper.yml"


@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.exists()


def test_workflow_is_valid_yaml(workflow):
    assert isinstance(workflow, dict)


def test_workflow_has_expected_triggers(workflow):
    # YAML parses bare `on:` key as boolean True in PyYAML.
    triggers = workflow.get(True) or workflow.get("on")
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_has_expected_jobs(workflow):
    jobs = workflow["jobs"]
    assert "test" in jobs
    assert "bump-version" in jobs


def test_bump_version_job_depends_on_test_job(workflow):
    assert workflow["jobs"]["bump-version"]["needs"] == "test"


def test_workflow_declares_read_permissions(workflow):
    assert workflow["permissions"]["contents"] == "read"


def test_workflow_references_existing_script():
    assert (REPO_ROOT / "bumper.py").exists()
    text = WORKFLOW_PATH.read_text()
    assert "bumper.py" in text


def test_workflow_references_existing_test_directory():
    assert (REPO_ROOT / "tests").is_dir()
    text = WORKFLOW_PATH.read_text()
    assert "tests/" in text


def test_fixture_files_referenced_exist():
    for fixture in ["commits_feat.txt", "commits_fix.txt", "commits_breaking.txt"]:
        assert (REPO_ROOT / "fixtures" / fixture).exists()


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed")
    proc = subprocess.run(
        [actionlint, str(WORKFLOW_PATH)], capture_output=True, text=True
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
