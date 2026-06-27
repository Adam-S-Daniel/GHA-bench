"""
Workflow tests: static structure checks + end-to-end execution through `act`.

Per the task requirements, the cleanup script is exercised ONLY through the
GitHub Actions pipeline (never invoked directly here). Each act test case:

  * builds a throwaway git repo containing the project files + that case's
    fixture data,
  * runs `act push --rm`,
  * appends the full output (clearly delimited) to ./act-result.txt,
  * asserts act exited 0, the job succeeded, and the printed summary matches the
    EXACT known-good values for that input.

To respect the "few act runs" guidance there are exactly two act cases.
"""

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_DIR = Path(__file__).resolve().parent
WORKFLOW = PROJECT_DIR / ".github" / "workflows" / "artifact-cleanup-script.yml"
ACT_RESULT = PROJECT_DIR / "act-result.txt"


# ---------------------------------------------------------------------------
# Static structure tests
# ---------------------------------------------------------------------------

def _load_workflow():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert WORKFLOW.is_file(), f"missing workflow file: {WORKFLOW}"


def test_workflow_has_expected_triggers():
    wf = _load_workflow()
    # YAML parses the `on:` key as the boolean True, so check both spellings.
    triggers = wf.get("on", wf.get(True))
    assert triggers is not None
    for ev in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert ev in triggers, f"expected trigger {ev!r}"


def test_workflow_has_least_privilege_permissions():
    wf = _load_workflow()
    assert wf["permissions"]["contents"] == "read"


def test_workflow_job_and_steps_structure():
    wf = _load_workflow()
    assert "cleanup" in wf["jobs"]
    steps = wf["jobs"]["cleanup"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses)
    assert any(u.startswith("actions/setup-python@") for u in uses)
    # The script must actually be invoked somewhere.
    run_blob = "\n".join(s.get("run", "") for s in steps)
    assert "artifact_cleanup.py" in run_blob


def test_workflow_references_existing_files():
    """Every project path the workflow depends on must exist on disk."""
    assert (PROJECT_DIR / "artifact_cleanup.py").is_file()
    assert (PROJECT_DIR / "fixtures" / "artifacts.json").is_file()
    assert (PROJECT_DIR / "fixtures" / "policy.json").is_file()


def test_actionlint_passes():
    proc = subprocess.run(
        ["actionlint", str(WORKFLOW)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


# ---------------------------------------------------------------------------
# act end-to-end tests
# ---------------------------------------------------------------------------

# Each case overrides the fixture files; CLEANUP_NOW in the workflow is fixed at
# 2026-06-26T12:00:00Z, so all dates below are relative to that.
ACT_CASES = [
    {
        "id": "combined-policies",
        "artifacts": {
            "artifacts": [
                {"name": "ci-build-a", "size_bytes": 100, "created_at": "2026-05-07T12:00:00Z", "run_id": 1, "workflow": "ci"},
                {"name": "ci-build-b", "size_bytes": 100, "created_at": "2026-05-17T12:00:00Z", "run_id": 2, "workflow": "ci"},
                {"name": "ci-build-c", "size_bytes": 100, "created_at": "2026-06-16T12:00:00Z", "run_id": 3, "workflow": "ci"},
                {"name": "release-r1", "size_bytes": 500, "created_at": "2026-04-27T12:00:00Z", "run_id": 4, "workflow": "release"},
                {"name": "release-r2", "size_bytes": 500, "created_at": "2026-06-21T12:00:00Z", "run_id": 5, "workflow": "release"},
            ]
        },
        "policy": {"keep_latest_per_workflow": 1, "max_age_days": 30, "max_total_size_bytes": 1000},
        "expected": {
            "Total artifacts": 5,
            "To delete": 3,
            "To retain": 2,
            "Space reclaimed": 700,
            "Space retained": 600,
        },
    },
    {
        "id": "max-total-size-squeeze",
        "artifacts": {
            "artifacts": [
                {"name": "x", "size_bytes": 100, "created_at": "2026-06-23T12:00:00Z", "run_id": 10, "workflow": "ci"},
                {"name": "y", "size_bytes": 100, "created_at": "2026-06-24T12:00:00Z", "run_id": 11, "workflow": "ci"},
                {"name": "z", "size_bytes": 100, "created_at": "2026-06-25T12:00:00Z", "run_id": 12, "workflow": "ci"},
            ]
        },
        "policy": {"max_total_size_bytes": 250},
        "expected": {
            "Total artifacts": 3,
            "To delete": 1,
            "To retain": 2,
            "Space reclaimed": 100,
            "Space retained": 200,
        },
    },
]


def _have_act():
    return shutil.which("act") is not None and shutil.which("docker") is not None


def _setup_repo(dest: Path, case: dict):
    """Copy project files into a fresh git repo and inject the case fixtures."""
    (dest / ".github" / "workflows").mkdir(parents=True)
    (dest / "fixtures").mkdir()
    shutil.copy(PROJECT_DIR / "artifact_cleanup.py", dest / "artifact_cleanup.py")
    shutil.copy(WORKFLOW, dest / ".github" / "workflows" / "artifact-cleanup-script.yml")
    actrc = PROJECT_DIR / ".actrc"
    if actrc.is_file():
        shutil.copy(actrc, dest / ".actrc")
    # Inject this case's fixture data.
    (dest / "fixtures" / "artifacts.json").write_text(
        json.dumps(case["artifacts"]), encoding="utf-8"
    )
    (dest / "fixtures" / "policy.json").write_text(
        json.dumps(case["policy"]), encoding="utf-8"
    )
    subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
    subprocess.run(["git", "config", "user.email", "t@t.t"], cwd=dest, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=dest, check=True)
    subprocess.run(["git", "add", "-A"], cwd=dest, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "test"], cwd=dest, check=True)


@pytest.fixture(scope="session", autouse=True)
def _reset_act_result():
    """Start each test session with a fresh act-result.txt."""
    if ACT_RESULT.exists():
        ACT_RESULT.unlink()
    yield


@pytest.mark.skipif(not _have_act(), reason="act/docker not available")
@pytest.mark.parametrize("case", ACT_CASES, ids=[c["id"] for c in ACT_CASES])
def test_workflow_runs_through_act(tmp_path, case):
    repo = tmp_path / "repo"
    repo.mkdir()
    _setup_repo(repo, case)

    proc = subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=600,
    )
    output = proc.stdout + "\n" + proc.stderr

    # Persist the full output, clearly delimited, for inspection.
    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 70}\n")
        fh.write(f"TEST CASE: {case['id']}\n")
        fh.write(f"act exit code: {proc.returncode}\n")
        fh.write(f"{'=' * 70}\n")
        fh.write(output)
        fh.write("\n")

    assert proc.returncode == 0, f"act failed for {case['id']} (see act-result.txt)"
    assert "Job succeeded" in output, f"job did not succeed for {case['id']}"

    # Assert on EXACT expected values parsed from the printed summary.
    for label, value in case["expected"].items():
        # e.g. "Space reclaimed: 700 bytes" / "Total artifacts: 5"
        pattern = rf"{re.escape(label)}:\s*{value}\b"
        assert re.search(pattern, output), (
            f"[{case['id']}] expected '{label}: {value}' in act output"
        )
