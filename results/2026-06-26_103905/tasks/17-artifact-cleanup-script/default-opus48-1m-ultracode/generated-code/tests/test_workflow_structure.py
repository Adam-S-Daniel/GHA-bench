"""
Structure tests for the GitHub Actions workflow.

These verify the workflow YAML statically (no Docker needed): that it parses,
declares the expected triggers/jobs/steps, references files that actually exist
on disk, and passes ``actionlint``. They are part of the normal, fast test suite.
"""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = PROJECT_ROOT / ".github" / "workflows" / "artifact-cleanup-script.yml"
EXPECTED_CASES = ["keep_n", "age", "size", "combined", "empty"]


@pytest.fixture(scope="module")
def workflow() -> dict:
    assert WORKFLOW.exists(), f"workflow file missing: {WORKFLOW}"
    return yaml.safe_load(WORKFLOW.read_text())


def _triggers(wf: dict):
    """Return the 'on:' mapping. PyYAML (YAML 1.1) parses the bare key ``on``
    as the boolean ``True``, so accept either form."""
    return wf.get("on", wf.get(True))


def test_workflow_parses(workflow):
    assert isinstance(workflow, dict)
    assert workflow["name"] == "Artifact Cleanup"


def test_expected_triggers_present(workflow):
    triggers = _triggers(workflow)
    assert triggers is not None, "workflow has no 'on:' triggers"
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"


def test_permissions_declared(workflow):
    perms = workflow.get("permissions")
    assert perms == {"contents": "read", "actions": "write"}


def test_jobs_and_dependency(workflow):
    jobs = workflow["jobs"]
    assert "cleanup" in jobs
    assert "summary" in jobs
    # summary depends on cleanup (job dependency requirement).
    assert jobs["summary"]["needs"] == "cleanup"
    assert jobs["cleanup"]["runs-on"] == "ubuntu-latest"


def test_matrix_covers_all_cases(workflow):
    matrix = workflow["jobs"]["cleanup"]["strategy"]["matrix"]
    assert sorted(matrix["case"]) == sorted(EXPECTED_CASES)


def test_steps_use_checkout_and_run_script(workflow):
    steps = workflow["jobs"]["cleanup"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    runs = "\n".join(s.get("run", "") for s in steps)
    assert any(u.startswith("actions/checkout@v4") for u in uses), "checkout@v4 missing"
    assert "artifact_cleanup.py" in runs, "workflow does not invoke the script"
    assert "--dry-run" in runs, "workflow should exercise dry-run mode"


def test_referenced_script_exists():
    assert (PROJECT_ROOT / "artifact_cleanup.py").exists()


def test_referenced_fixtures_exist():
    for case in EXPECTED_CASES:
        fx = PROJECT_ROOT / "fixtures" / f"{case}.json"
        assert fx.exists(), f"fixture referenced by the matrix is missing: {fx}"


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        [actionlint, str(WORKFLOW)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"actionlint failed:\n{result.stdout}\n{result.stderr}"
    )
