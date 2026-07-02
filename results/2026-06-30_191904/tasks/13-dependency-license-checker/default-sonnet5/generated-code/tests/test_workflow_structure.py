"""
Structure tests for the GitHub Actions workflow itself.

These tests do NOT go through `act` -- they statically inspect the workflow
YAML and validate it with `actionlint`, per the "Workflow Structure Tests"
requirement. They are plain pytest tests, runnable directly, and are the
first thing written (red) before the workflow file exists (green).
"""
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "dependency-license-checker.yml"


def _load_workflow():
    assert WORKFLOW_PATH.is_file(), f"workflow file missing: {WORKFLOW_PATH}"
    with WORKFLOW_PATH.open() as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_has_expected_triggers():
    doc = _load_workflow()
    # YAML parses the bare key `on:` as the boolean True unless quoted.
    triggers = doc.get("on") or doc.get(True)
    assert triggers is not None, "workflow has no 'on' trigger section"
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_has_a_job_with_checkout_and_python_steps():
    doc = _load_workflow()
    jobs = doc.get("jobs")
    assert jobs, "workflow defines no jobs"

    job = next(iter(jobs.values()))
    steps = job.get("steps", [])
    uses_list = [s.get("uses", "") for s in steps]

    assert any(u.startswith("actions/checkout@") for u in uses_list), \
        "job does not check out the repository"
    assert any(u.startswith("actions/setup-python@") for u in uses_list), \
        "job does not set up Python"


def test_workflow_has_appropriate_permissions():
    doc = _load_workflow()
    assert "permissions" in doc, "workflow should declare explicit permissions"
    assert doc["permissions"].get("contents") == "read"


def test_workflow_references_script_and_config_files_that_exist():
    doc = _load_workflow()
    jobs = doc.get("jobs")
    job = next(iter(jobs.values()))
    run_text = "\n".join(s.get("run", "") for s in job.get("steps", []))

    assert "license_checker.py" in run_text
    assert (REPO_ROOT / "license_checker.py").is_file(), \
        "workflow references license_checker.py but it does not exist"
    assert (REPO_ROOT / "policy.json").is_file(), \
        "workflow references policy.json but it does not exist"
    assert (REPO_ROOT / "license_db.json").is_file(), \
        "workflow references license_db.json but it does not exist"


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW_PATH)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"actionlint failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    )
