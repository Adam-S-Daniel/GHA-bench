"""Structure tests for the GitHub Actions workflow.

These run on the host (not inside act) because they need the repo layout
and the actionlint binary. They verify:
  - the YAML parses and has the expected triggers/jobs/steps,
  - every file the workflow references actually exists,
  - actionlint exits 0.
"""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "artifact-cleanup-script.yml"


@pytest.fixture(scope="module")
def workflow():
    return yaml.safe_load(WORKFLOW.read_text())


class TestWorkflowStructure:
    def test_workflow_file_exists(self):
        assert WORKFLOW.is_file()

    def test_triggers(self, workflow):
        # PyYAML parses the `on:` key as boolean True
        triggers = workflow.get("on", workflow.get(True))
        assert "push" in triggers
        assert "workflow_dispatch" in triggers
        assert "schedule" in triggers

    def test_permissions_are_read_only(self, workflow):
        assert workflow["permissions"] == {"contents": "read"}

    def test_jobs_and_dependency(self, workflow):
        jobs = workflow["jobs"]
        assert set(jobs) == {"unit-tests", "cleanup-plan"}
        assert jobs["cleanup-plan"]["needs"] == "unit-tests"

    def test_jobs_check_out_the_repo(self, workflow):
        for job in workflow["jobs"].values():
            uses = [s.get("uses", "") for s in job["steps"]]
            assert any(u.startswith("actions/checkout@v4") for u in uses)

    def test_referenced_files_exist(self, workflow):
        # every project path mentioned in run steps must exist in the repo
        for path in (
            "artifact_cleanup.py",
            "fixtures/artifacts.json",
            "cleanup-config.env",
            "tests/test_artifact_cleanup.py",
            "tests/test_cli.py",
        ):
            assert (REPO_ROOT / path).is_file(), f"missing {path}"
            run_text = yaml.dump(workflow["jobs"])
            if path.startswith("tests/") or path == "artifact_cleanup.py":
                assert path in run_text, f"workflow does not reference {path}"

    def test_cleanup_job_runs_the_script_on_the_fixture(self, workflow):
        run_step = workflow["jobs"]["cleanup-plan"]["steps"][-1]["run"]
        assert "python3 artifact_cleanup.py" in run_step
        assert "--input fixtures/artifacts.json" in run_step


class TestActionlint:
    @pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
    def test_actionlint_passes(self):
        result = subprocess.run(
            ["actionlint", str(WORKFLOW)], capture_output=True, text=True
        )
        assert result.returncode == 0, result.stdout + result.stderr
