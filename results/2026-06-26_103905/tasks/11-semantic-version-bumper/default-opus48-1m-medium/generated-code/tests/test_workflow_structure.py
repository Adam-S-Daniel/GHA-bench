"""
Static checks on the GitHub Actions workflow itself:
  - it is valid YAML with the expected triggers, job, and steps,
  - every script/path it references actually exists,
  - actionlint validates it with exit code 0.

These run fast and require no Docker, so they guard the workflow's shape
independently of the (slow) `act` end-to-end harness.
"""

import os
import shutil
import subprocess

import pytest
import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(PROJECT_ROOT, ".github", "workflows", "semantic-version-bumper.yml")


@pytest.fixture(scope="module")
def wf():
    with open(WORKFLOW, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.exists(WORKFLOW)


def test_has_expected_triggers(wf):
    # PyYAML parses the bare `on:` key as the boolean True.
    triggers = wf.get(True, wf.get("on"))
    assert triggers is not None
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"


def test_has_minimal_permissions(wf):
    assert wf.get("permissions", {}).get("contents") == "read"


def test_has_bump_job_with_steps(wf):
    jobs = wf["jobs"]
    assert "bump" in jobs
    steps = jobs["bump"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses)
    assert any(u.startswith("actions/setup-python@v5") for u in uses)
    # The bumper must actually be invoked.
    run_blob = "\n".join(s.get("run", "") for s in steps)
    assert "version_bumper.py" in run_blob


def test_referenced_script_exists():
    assert os.path.exists(os.path.join(PROJECT_ROOT, "version_bumper.py"))


def test_runner_is_ubuntu(wf):
    assert wf["jobs"]["bump"]["runs-on"] == "ubuntu-latest"


@pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
def test_actionlint_passes():
    proc = subprocess.run(
        ["actionlint", WORKFLOW], capture_output=True, text=True
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
