"""
Structural checks for the GitHub Actions workflow itself: valid YAML,
expected triggers/jobs/steps, correct script references, and a clean
actionlint run. These are separate from the act-based execution tests
in act-result.txt (also required) which prove the workflow actually runs.
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parent.parent
WORKFLOW_PATH = ROOT / ".github" / "workflows" / "secret-rotation-validator.yml"


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_is_valid_yaml():
    with open(WORKFLOW_PATH) as f:
        doc = yaml.safe_load(f)
    assert isinstance(doc, dict)


def _load():
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_has_expected_triggers():
    doc = _load()
    # PyYAML parses the bare key "on" as boolean True.
    triggers = doc.get(True, doc.get("on"))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_has_test_and_validate_jobs():
    doc = _load()
    jobs = doc["jobs"]
    assert "test" in jobs
    assert "validate" in jobs


def test_validate_job_depends_on_test_job():
    doc = _load()
    assert doc["jobs"]["validate"]["needs"] == "test"


def test_workflow_declares_read_only_permissions():
    doc = _load()
    assert doc["permissions"] == {"contents": "read"}


def test_workflow_references_existing_script_and_fixtures():
    doc = _load()
    steps_text = str(doc["jobs"]["validate"]["steps"])
    assert "secret_rotation_validator.py" in steps_text
    assert (ROOT / "secret_rotation_validator.py").is_file()
    assert (ROOT / "fixtures" / "secrets_config.json").is_file()
    assert (ROOT / "fixtures" / "secrets_config_clean.json").is_file()


def test_test_job_runs_pytest_suite():
    doc = _load()
    steps_text = str(doc["jobs"]["test"]["steps"])
    assert "pytest tests/" in steps_text


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed in this environment")
    result = subprocess.run([actionlint, str(WORKFLOW_PATH)], capture_output=True, text=True)
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
