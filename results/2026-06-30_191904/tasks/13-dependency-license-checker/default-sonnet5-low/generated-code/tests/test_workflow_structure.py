"""
Static structural tests for the GitHub Actions workflow. These do not
invoke act - they check the YAML shape, that referenced files exist, and
that actionlint is clean. The functional/behavioral tests of the pipeline
itself run through act (see run_act_tests.py / act-result.txt).
"""
import os
import shutil
import subprocess

import pytest
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(ROOT, ".github", "workflows", "dependency-license-checker.yml")


def load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_has_expected_triggers():
    wf = load_workflow()
    # PyYAML parses the bare key `on` as boolean True.
    triggers = wf.get("on", wf.get(True))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_expected_jobs_and_dependency():
    wf = load_workflow()
    jobs = wf["jobs"]
    assert "unit-tests" in jobs
    assert "compliance-check" in jobs
    assert jobs["compliance-check"]["needs"] == "unit-tests"


def test_workflow_permissions_are_minimal():
    wf = load_workflow()
    assert wf["permissions"]["contents"] == "read"


def test_workflow_references_existing_script_and_fixtures():
    wf = load_workflow()
    steps_text = " ".join(
        step.get("run", "")
        for job in wf["jobs"].values()
        for step in job["steps"]
    )
    assert "license_checker.py" in steps_text
    assert os.path.isfile(os.path.join(ROOT, "license_checker.py"))
    assert os.path.isfile(os.path.join(ROOT, "fixtures", "package.json"))
    assert os.path.isfile(os.path.join(ROOT, "fixtures", "license-policy.json"))
    assert os.path.isfile(os.path.join(ROOT, "fixtures", "license-db.json"))


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if not actionlint:
        pytest.skip("actionlint not installed in this environment")
    result = subprocess.run(
        [actionlint, WORKFLOW_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
