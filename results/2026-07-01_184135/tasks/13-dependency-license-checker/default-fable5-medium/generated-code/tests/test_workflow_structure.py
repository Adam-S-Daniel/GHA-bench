"""Structure tests for the GitHub Actions workflow.

These verify the workflow YAML itself: expected triggers, jobs, steps,
job dependencies, that every file the workflow references actually
exists in the repo, and that actionlint accepts the file. The actionlint
test is skipped where the binary is unavailable (e.g. inside the act
container) and runs on the host via the test harness.
"""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = PROJECT_ROOT / ".github" / "workflows" / "dependency-license-checker.yml"


@pytest.fixture(scope="module")
def workflow():
    assert WORKFLOW.is_file(), f"workflow file missing: {WORKFLOW}"
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def test_triggers(workflow):
    # PyYAML parses the bare 'on' key as boolean True.
    triggers = workflow.get("on", workflow.get(True))
    assert set(triggers) == {"push", "pull_request", "workflow_dispatch", "schedule"}
    assert triggers["schedule"] == [{"cron": "0 6 * * 1"}]


def test_permissions_are_least_privilege(workflow):
    assert workflow["permissions"] == {"contents": "read"}


def test_jobs_and_dependencies(workflow):
    jobs = workflow["jobs"]
    assert set(jobs) == {"test", "license-report"}
    assert jobs["license-report"]["needs"] == "test"
    for job in jobs.values():
        assert job["runs-on"] == "ubuntu-latest"


def test_every_job_checks_out_with_checkout_v4(workflow):
    for name, job in workflow["jobs"].items():
        uses = [step.get("uses", "") for step in job["steps"]]
        assert "actions/checkout@v4" in uses, f"job {name} missing checkout@v4"


def test_workflow_runs_pytest_and_the_checker_script(workflow):
    jobs = workflow["jobs"]
    test_cmds = " ".join(s.get("run", "") for s in jobs["test"]["steps"])
    assert "pytest tests/" in test_cmds
    report_cmds = " ".join(s.get("run", "") for s in jobs["license-report"]["steps"])
    assert "license_checker.py" in report_cmds


def test_referenced_paths_exist(workflow):
    # Every repo-relative path mentioned in run steps must exist, so the
    # workflow cannot silently drift away from the actual file layout.
    for rel in ("license_checker.py", "tests", "fixtures/config.json",
                "fixtures/mock_licenses.json", "test-data/manifest"):
        assert (PROJECT_ROOT / rel).exists(), f"workflow references missing path: {rel}"


@pytest.mark.skipif(shutil.which("actionlint") is None,
                    reason="actionlint not installed in this environment")
def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW)], capture_output=True, text=True, cwd=PROJECT_ROOT
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}{result.stderr}"
