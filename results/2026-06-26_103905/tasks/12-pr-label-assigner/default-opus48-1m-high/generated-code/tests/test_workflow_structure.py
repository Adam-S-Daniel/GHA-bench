"""Structural tests for the GitHub Actions workflow.

These run on the host (not in a container) and assert that the workflow file is
well-formed, references files that actually exist, and passes actionlint. They
complement the behavioural validation performed end-to-end through ``act`` in
``run_act_tests.py``.
"""

import os
import shutil
import subprocess

import pytest
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "pr-label-assigner.yml")


@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        # PyYAML parses the GitHub Actions `on:` key as the boolean True, so we
        # load normally and account for that quirk in the trigger test below.
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW)


def test_expected_triggers_present(workflow):
    triggers = workflow.get("on", workflow.get(True))
    assert triggers is not None
    for event in ("push", "pull_request", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"


def test_permissions_declared(workflow):
    perms = workflow["permissions"]
    assert perms["contents"] == "read"
    assert perms["pull-requests"] == "write"


def test_jobs_and_dependency_present(workflow):
    jobs = workflow["jobs"]
    assert "assign-labels" in jobs
    assert "summary" in jobs
    # The summary job must depend on the label-computing job.
    assert jobs["summary"]["needs"] == "assign-labels"


def test_checkout_action_pinned(workflow):
    steps = workflow["jobs"]["assign-labels"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert "actions/checkout@v4" in uses


def test_workflow_references_existing_script(workflow):
    steps = workflow["jobs"]["assign-labels"]["steps"]
    run_blocks = "\n".join(s.get("run", "") for s in steps)
    assert "label_assigner.py" in run_blocks
    # The referenced script must actually exist on disk.
    assert os.path.isfile(os.path.join(ROOT, "label_assigner.py"))


def test_referenced_config_default_exists():
    # The default config the workflow falls back to must exist in the repo.
    assert os.path.isfile(os.path.join(ROOT, "rules.json"))


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        ["actionlint", WORKFLOW],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
