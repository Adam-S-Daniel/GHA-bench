"""
Structure tests for the GitHub Actions workflow.

These tests never invoke `act` -- they just parse the workflow YAML and check
its shape, confirm the files it references actually exist in the repo, and
run `actionlint` as a subprocess. They are fast (no Docker) and are meant to
catch authoring mistakes before we ever pay for a slow `act push` run.
"""
import subprocess
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "secret-rotation-validator.yml"


def load_workflow():
    assert WORKFLOW_PATH.exists(), f"workflow file missing: {WORKFLOW_PATH}"
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file()


def test_workflow_has_expected_triggers():
    workflow = load_workflow()
    # PyYAML (YAML 1.1) parses the bare key `on` as the boolean True, so the
    # trigger map can land under either "on" or True depending on version.
    triggers = workflow.get("on", workflow.get(True))
    assert triggers is not None, "workflow has no 'on' trigger section"
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_schedule_has_a_cron_expression():
    workflow = load_workflow()
    triggers = workflow.get("on", workflow.get(True))
    schedules = triggers["schedule"]
    assert isinstance(schedules, list) and len(schedules) >= 1
    assert "cron" in schedules[0]


def test_workflow_has_permissions_declared():
    workflow = load_workflow()
    assert "permissions" in workflow, "workflow should declare least-privilege permissions"


def test_workflow_has_validate_secrets_job():
    workflow = load_workflow()
    jobs = workflow["jobs"]
    assert "validate-secrets" in jobs
    job = jobs["validate-secrets"]
    assert job["runs-on"] == "ubuntu-latest"


def test_workflow_job_has_checkout_and_python_setup_and_run_steps():
    workflow = load_workflow()
    steps = workflow["jobs"]["validate-secrets"]["steps"]
    uses_list = [s.get("uses", "") for s in steps]
    run_list = [s.get("run", "") for s in steps]

    assert any(u.startswith("actions/checkout@") for u in uses_list), "missing checkout step"
    assert any(u.startswith("actions/setup-python@") for u in uses_list), "missing setup-python step"
    assert any("secret_rotation_validator.py" in r for r in run_list), (
        "no step invokes secret_rotation_validator.py"
    )


def test_workflow_references_script_that_exists():
    """The workflow must call a script file that actually exists in the repo."""
    workflow = load_workflow()
    steps = workflow["jobs"]["validate-secrets"]["steps"]
    run_text = "\n".join(s.get("run", "") for s in steps)
    assert "secret_rotation_validator.py" in run_text
    script_path = REPO_ROOT / "secret_rotation_validator.py"
    assert script_path.is_file(), f"referenced script does not exist: {script_path}"


def test_workflow_references_fixture_that_exists():
    """The workflow reads a config path that must exist as a real fixture file."""
    workflow = load_workflow()
    steps = workflow["jobs"]["validate-secrets"]["steps"]
    env = workflow.get("env", {})
    config_path = env.get("CONFIG_PATH")
    assert config_path, "workflow env.CONFIG_PATH is not set"
    assert (REPO_ROOT / config_path).is_file(), f"fixture referenced by workflow missing: {config_path}"


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW_PATH)],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    assert result.returncode == 0, f"actionlint failed:\nstdout={result.stdout}\nstderr={result.stderr}"
