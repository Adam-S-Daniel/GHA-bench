"""Workflow structure tests: triggers, jobs, steps, script paths, actionlint.

These validate the GitHub Actions workflow itself. The actionlint check is
skipped when the binary is unavailable (e.g. inside the act container); the
local harness runs it where actionlint is installed.
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

REPO = Path(__file__).resolve().parent.parent
WORKFLOW = REPO / ".github" / "workflows" / "test-results-aggregator.yml"


@pytest.fixture(scope="module")
def wf():
    return yaml.safe_load(WORKFLOW.read_text())


def triggers(wf):
    # PyYAML parses the unquoted key `on:` as boolean True (YAML 1.1).
    return wf.get("on", wf.get(True))


def test_workflow_file_exists():
    assert WORKFLOW.is_file()


def test_workflow_has_expected_triggers(wf):
    t = triggers(wf)
    assert set(t) == {"push", "pull_request", "schedule", "workflow_dispatch"}
    assert t["schedule"] == [{"cron": "17 5 * * *"}]


def test_workflow_permissions_are_least_privilege(wf):
    assert wf["permissions"] == {"contents": "read"}


def test_workflow_jobs_and_dependencies(wf):
    jobs = wf["jobs"]
    assert set(jobs) == {"unit-tests", "aggregate-results"}
    assert jobs["aggregate-results"]["needs"] == "unit-tests"
    for job in jobs.values():
        assert job["runs-on"] == "ubuntu-latest"
        # Every job checks out the repo with a pinned major version.
        assert any(s.get("uses", "").startswith("actions/checkout@v4")
                   for s in job["steps"])


def test_workflow_references_existing_paths(wf):
    """Every file/dir the workflow run steps reference must exist in the repo."""
    run_text = "\n".join(
        s.get("run", "") for job in wf["jobs"].values() for s in job["steps"])
    assert "python3 -m pytest tests/" in run_text
    assert 'python3 aggregator.py "${RESULTS_DIR:-fixtures}"' in run_text
    assert (REPO / "aggregator.py").is_file()
    assert (REPO / "tests").is_dir()
    assert (REPO / "fixtures").is_dir()
    assert list((REPO / "fixtures").glob("*.xml")) and list((REPO / "fixtures").glob("*.json"))


@pytest.mark.skipif(shutil.which("actionlint") is None,
                    reason="actionlint not installed in this environment")
def test_actionlint_passes():
    proc = subprocess.run(["actionlint", str(WORKFLOW)],
                          capture_output=True, text=True)
    assert proc.returncode == 0, proc.stdout + proc.stderr
