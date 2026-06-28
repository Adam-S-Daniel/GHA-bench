"""Structure tests for the GitHub Actions workflow.

These assert that the workflow is well-formed, references real files, wires up
job dependencies, and passes actionlint. They run on the host (not through
act) because they validate the pipeline definition itself.
"""

import os
import shutil
import subprocess

import pytest
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
WORKFLOW = os.path.join(HERE, ".github", "workflows", "artifact-cleanup-script.yml")


@pytest.fixture(scope="module")
def wf():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(wf):
    # PyYAML parses the bare key ``on`` as the boolean True (YAML 1.1), so the
    # trigger mapping can live under either key depending on the loader.
    return wf.get("on", wf.get(True))


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW)


def test_has_expected_triggers(wf):
    triggers = _triggers(wf)
    assert triggers is not None
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"
    # schedule must carry a cron expression
    assert triggers["schedule"][0]["cron"]


def test_has_read_permissions(wf):
    assert wf["permissions"]["contents"] == "read"


def test_jobs_and_dependency(wf):
    jobs = wf["jobs"]
    assert "unit-tests" in jobs
    assert "cleanup-plan" in jobs
    # cleanup-plan must depend on unit-tests passing first.
    assert jobs["cleanup-plan"]["needs"] == "unit-tests"


def test_uses_checkout_v4(wf):
    uses = [
        step.get("uses", "")
        for job in wf["jobs"].values()
        for step in job["steps"]
    ]
    assert any(u == "actions/checkout@v4" for u in uses)


def test_matrix_covers_all_fixtures(wf):
    include = wf["jobs"]["cleanup-plan"]["strategy"]["matrix"]["include"]
    cases = {entry["case"] for entry in include}
    assert cases == {"case_max_age", "case_keep_latest", "case_combined"}
    # Each referenced fixture file must actually exist on disk.
    for c in cases:
        assert os.path.isfile(os.path.join(HERE, "fixtures", f"{c}.json"))


def test_references_existing_script(wf):
    # The workflow invokes artifact_cleanup.py and installs requirements.txt.
    body = open(WORKFLOW, encoding="utf-8").read()
    assert "artifact_cleanup.py" in body
    assert os.path.isfile(os.path.join(HERE, "artifact_cleanup.py"))
    assert "requirements.txt" in body
    assert os.path.isfile(os.path.join(HERE, "requirements.txt"))


@pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", WORKFLOW], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
