"""
Structure tests for the GitHub Actions workflow file. These validate the
YAML shape (triggers/jobs/steps), that referenced script/fixture paths
exist on disk, and that actionlint passes -- without actually running the
workflow (that's covered separately by the act-based integration harness).
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parent
WORKFLOW_PATH = ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"


@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_has_expected_triggers(workflow):
    # PyYAML parses the bare "on" key as boolean True in YAML 1.1.
    triggers = workflow.get("on", workflow.get(True))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"


def test_workflow_has_permissions(workflow):
    assert workflow["permissions"]["contents"] == "read"


def test_workflow_has_expected_jobs(workflow):
    jobs = workflow["jobs"]
    assert set(jobs.keys()) == {"unit-tests", "generate-matrix", "build"}


def test_generate_matrix_depends_on_unit_tests(workflow):
    assert workflow["jobs"]["generate-matrix"]["needs"] == "unit-tests"


def test_build_depends_on_generate_matrix(workflow):
    assert workflow["jobs"]["build"]["needs"] == "generate-matrix"


def test_build_job_strategy_references_generated_matrix(workflow):
    strategy = workflow["jobs"]["build"]["strategy"]
    assert "needs.generate-matrix.outputs.matrix" in strategy["matrix"]
    assert "needs.generate-matrix.outputs.fail_fast" in strategy["fail-fast"]
    assert "needs.generate-matrix.outputs.max_parallel" in strategy["max-parallel"]


def test_all_jobs_use_checkout_action(workflow):
    for job_name, job in workflow["jobs"].items():
        step_uses = [s.get("uses", "") for s in job["steps"]]
        assert any(u.startswith("actions/checkout@") for u in step_uses), (
            f"job '{job_name}' does not check out the repository"
        )


def test_unit_tests_job_runs_pytest_against_script(workflow):
    steps = workflow["jobs"]["unit-tests"]["steps"]
    run_steps = " ".join(s.get("run", "") for s in steps)
    assert "pytest" in run_steps
    assert "test_matrix_generator.py" in run_steps


def test_generate_matrix_job_references_script_and_fixture(workflow):
    steps = workflow["jobs"]["generate-matrix"]["steps"]
    run_steps = " ".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in run_steps
    assert "fixtures/ci_matrix.json" in run_steps


def test_referenced_script_and_fixture_paths_exist():
    assert (ROOT / "matrix_generator.py").is_file()
    assert (ROOT / "fixtures" / "ci_matrix.json").is_file()
    assert (ROOT / "test_matrix_generator.py").is_file()


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    assert actionlint is not None, "actionlint must be installed"
    proc = subprocess.run(
        [actionlint, str(WORKFLOW_PATH)], capture_output=True, text=True
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
