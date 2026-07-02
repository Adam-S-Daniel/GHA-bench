"""
Structure/lint tests for .github/workflows/environment-matrix-generator.yml.

These validate the workflow file itself (YAML shape, script references,
actionlint) using host tools (PyYAML, the actionlint binary). They are run
directly on the host as part of the authoring/validation loop -- actionlint
is not installed inside the act Docker container, so this check inherently
can't run *through* act (it is validating the pipeline definition, not
exercising matrix_generator.py's logic, which is what the "run everything
through act" requirement targets).
"""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"


@pytest.fixture(scope="module")
def workflow_doc():
    with open(WORKFLOW_PATH) as f:
        # PyYAML parses the `on:` key as the boolean True unless quoted;
        # GitHub's own parser treats it as the string "on", so normalize.
        text = f.read()
    doc = yaml.safe_load(text)
    if True in doc:
        doc["on"] = doc.pop(True)
    return doc


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_is_valid_yaml(workflow_doc):
    assert isinstance(workflow_doc, dict)


def test_workflow_has_name(workflow_doc):
    assert workflow_doc.get("name") == "Environment Matrix Generator"


def test_workflow_triggers_include_required_events(workflow_doc):
    triggers = workflow_doc["on"]
    assert set(triggers.keys()) == {"push", "pull_request", "workflow_dispatch", "schedule"}
    assert triggers["schedule"] == [{"cron": "0 6 * * 1"}]


def test_workflow_declares_read_permissions(workflow_doc):
    assert workflow_doc.get("permissions") == {"contents": "read"}


def test_workflow_declares_env_vars(workflow_doc):
    env = workflow_doc.get("env", {})
    assert "PYTHON_VERSION" in env
    assert "MATRIX_CONFIG" in env


def test_workflow_has_expected_jobs(workflow_doc):
    jobs = workflow_doc["jobs"]
    assert set(jobs.keys()) == {"test", "generate-matrix", "use-matrix"}


def test_job_dependencies_are_wired_correctly(workflow_doc):
    jobs = workflow_doc["jobs"]
    assert "needs" not in jobs["test"]
    assert jobs["generate-matrix"]["needs"] == "test"
    assert jobs["use-matrix"]["needs"] == "generate-matrix"


def test_test_job_runs_pytest_suite(workflow_doc):
    steps = workflow_doc["jobs"]["test"]["steps"]
    run_commands = " ".join(s.get("run", "") for s in steps)
    assert "pytest" in run_commands
    assert "tests/test_matrix_generator.py" in run_commands


def test_generate_matrix_job_invokes_script(workflow_doc):
    steps = workflow_doc["jobs"]["generate-matrix"]["steps"]
    run_commands = " ".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in run_commands


def test_use_matrix_job_consumes_generated_matrix(workflow_doc):
    use_matrix_job = workflow_doc["jobs"]["use-matrix"]
    assert use_matrix_job["env"]["MATRIX_INCLUDE"] == "${{ needs.generate-matrix.outputs.matrix_include }}"


def test_workflow_references_existing_script_and_test_paths():
    assert (PROJECT_ROOT / "matrix_generator.py").is_file()
    assert (PROJECT_ROOT / "tests" / "test_matrix_generator.py").is_file()
    assert (PROJECT_ROOT / "fixtures" / "config_basic.json").is_file()


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    if actionlint is None:
        pytest.skip("actionlint not installed on this host")
    proc = subprocess.run(
        [actionlint, str(WORKFLOW_PATH)],
        capture_output=True,
        text=True,
        cwd=str(PROJECT_ROOT),
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
