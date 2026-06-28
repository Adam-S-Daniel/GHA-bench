"""Structural tests for the GitHub Actions workflow.

These run on the host (no Docker/act) and assert that the workflow has the
expected triggers, permissions, jobs/dependencies, that it references the
real script files, and that `actionlint` is happy.
"""

import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "semantic-version-bumper.yml"


def load_workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text())


def get_on(wf: dict):
    # PyYAML (YAML 1.1) parses the bare key `on:` as the boolean True.
    return wf[True] if True in wf else wf["on"]


def test_workflow_file_exists():
    assert WORKFLOW.is_file()


def test_has_expected_triggers():
    on = get_on(load_workflow())
    for trigger in ("push", "pull_request", "workflow_dispatch", "schedule"):
        assert trigger in on, f"missing trigger: {trigger}"


def test_workflow_dispatch_declares_commits_file_input():
    on = get_on(load_workflow())
    assert "commits_file" in on["workflow_dispatch"]["inputs"]


def test_has_least_privilege_permissions():
    wf = load_workflow()
    assert wf["permissions"]["contents"] == "read"


def test_jobs_present_with_dependency():
    jobs = load_workflow()["jobs"]
    assert "bump" in jobs
    assert "verify" in jobs
    # The verify job must depend on the bump job.
    assert jobs["verify"]["needs"] == "bump"


def test_bump_job_checks_out_and_runs_the_script():
    steps = load_workflow()["jobs"]["bump"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses), \
        "workflow must use actions/checkout@v4"
    run_blob = "\n".join(s.get("run", "") for s in steps)
    assert "semver_bumper.py" in run_blob, "workflow must invoke semver_bumper.py"


def test_bump_job_exposes_outputs_consumed_by_verify():
    jobs = load_workflow()["jobs"]
    assert "new_version" in jobs["bump"]["outputs"]
    verify_run = "\n".join(s.get("run", "") for s in jobs["verify"]["steps"])
    assert "NEW_VERSION" in verify_run


def test_referenced_files_exist_on_disk():
    # The paths the workflow relies on must actually be present.
    assert (ROOT / "semver_bumper.py").is_file()
    assert (ROOT / "VERSION").is_file()
    assert (ROOT / "commits.log").is_file()


def test_actionlint_passes_cleanly():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW)], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
