"""Structure & static-analysis tests for the GitHub Actions workflow.

These run on the host (fast, no Docker). They guard the YAML shape, confirm the
workflow points at files that really exist, and assert that ``actionlint`` is
happy. The end-to-end execution-in-a-container tests live in
``test_workflow_act.py``.
"""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "artifact-cleanup-script.yml"


@pytest.fixture(scope="module")
def workflow():
    return yaml.safe_load(WORKFLOW.read_text())


def _triggers(wf):
    """Return the `on:` mapping.

    YAML 1.1 (PyYAML) parses the bare key ``on`` as the boolean ``True``, so we
    look it up under both spellings.
    """
    return wf.get("on", wf.get(True))


def test_workflow_file_exists():
    assert WORKFLOW.is_file(), f"workflow file missing: {WORKFLOW}"


def test_has_all_expected_triggers(workflow):
    triggers = _triggers(workflow)
    assert triggers is not None
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"
    # schedule must carry a cron entry.
    assert triggers["schedule"][0]["cron"] == "0 3 * * 1"


def test_has_least_privilege_permissions(workflow):
    assert workflow["permissions"]["contents"] == "read"


def test_jobs_and_dependency(workflow):
    jobs = workflow["jobs"]
    assert set(jobs) == {"validate", "cleanup"}
    # The cleanup job must depend on the validate job.
    assert jobs["cleanup"]["needs"] == "validate"


def test_runs_on_ubuntu(workflow):
    for job in workflow["jobs"].values():
        assert job["runs-on"] == "ubuntu-latest"


def test_uses_checkout_v4(workflow):
    steps = workflow["jobs"]["cleanup"]["steps"]
    assert any(s.get("uses") == "actions/checkout@v4" for s in steps)


def test_workflow_references_existing_script():
    """The workflow must invoke the real script, and that file must exist."""
    text = WORKFLOW.read_text()
    assert "artifact_cleanup.py" in text
    assert (ROOT / "artifact_cleanup.py").is_file()


def test_referenced_fixture_paths_exist(workflow):
    """Env-declared fixture files must exist on disk."""
    env = workflow["env"]
    for key in ("ARTIFACTS_FILE", "POLICY_FILE"):
        rel = env[key]
        assert (ROOT / rel).is_file(), f"fixture referenced by {key} not found: {rel}"


def test_actionlint_passes():
    """actionlint must exit 0 on the workflow file."""
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        [actionlint, str(WORKFLOW)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
