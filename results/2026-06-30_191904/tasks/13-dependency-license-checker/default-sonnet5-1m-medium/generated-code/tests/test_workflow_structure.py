"""
Structural checks on the GitHub Actions workflow itself: valid YAML,
expected triggers/jobs/steps, referenced script paths exist, and
actionlint passes cleanly.
"""
import os
import shutil
import subprocess

import yaml
import pytest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(
    PROJECT_ROOT, ".github", "workflows", "dependency-license-checker.yml"
)


@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_has_expected_triggers(workflow):
    # PyYAML parses the bare `on:` key as boolean True.
    triggers = workflow[True] if True in workflow else workflow["on"]
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_has_expected_jobs_and_dependency(workflow):
    jobs = workflow["jobs"]
    assert "unit-tests" in jobs
    assert "license-check" in jobs
    assert jobs["license-check"]["needs"] == "unit-tests"


def test_permissions_are_least_privilege(workflow):
    assert workflow["permissions"]["contents"] == "read"


def test_jobs_use_checkout_action(workflow):
    for job_name, job in workflow["jobs"].items():
        step_uses = [step.get("uses", "") for step in job["steps"]]
        assert any(u.startswith("actions/checkout@") for u in step_uses), job_name


def test_referenced_script_paths_exist(workflow):
    referenced_scripts = ["main.py", "manifest_parser.py", "license_checker.py",
                           "registry_lookup.py", "report.py", "config.py"]
    for script in referenced_scripts:
        assert os.path.isfile(os.path.join(PROJECT_ROOT, script)), script

    referenced_fixtures = [
        "fixtures/package.json",
        "fixtures/license-config.json",
        "fixtures/license-data.json",
    ]
    for fixture in referenced_fixtures:
        assert os.path.isfile(os.path.join(PROJECT_ROOT, fixture)), fixture


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        [actionlint, WORKFLOW_PATH], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
