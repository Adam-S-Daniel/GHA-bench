"""Workflow structure tests.

These parse the workflow YAML, assert its shape (triggers / jobs / steps),
confirm it references files that actually exist, and assert that actionlint
passes (exit code 0). They run locally (not inside the container) because they
inspect the repository and shell out to actionlint.
"""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

# tests/integration/this_file -> repo root is two levels up.
REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github" / "workflows" / "secret-rotation-validator.yml"


def _load_workflow() -> dict:
    with open(WORKFLOW, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _on_section(workflow: dict) -> dict:
    # YAML's "Norway problem": the bare key `on` is parsed as the boolean True
    # by a spec-compliant loader, so look it up under both keys.
    return workflow.get("on", workflow.get(True))


def test_workflow_file_exists():
    assert WORKFLOW.is_file(), f"workflow file missing: {WORKFLOW}"


def test_workflow_is_valid_yaml_with_name():
    workflow = _load_workflow()
    assert workflow["name"] == "Secret Rotation Validator"


def test_workflow_declares_all_expected_triggers():
    on = _on_section(_load_workflow())
    assert {"push", "pull_request", "schedule", "workflow_dispatch"}.issubset(on)
    # schedule must carry a cron entry.
    assert on["schedule"][0]["cron"]


def test_workflow_has_least_privilege_permissions():
    workflow = _load_workflow()
    assert workflow["permissions"]["contents"] == "read"


def test_workflow_defines_env_defaults():
    workflow = _load_workflow()
    assert "CONFIG_FILE" in workflow["env"]


def test_workflow_has_two_jobs_with_dependency():
    jobs = _load_workflow()["jobs"]
    assert "unit-tests" in jobs
    assert "rotation-report" in jobs
    # The report job must depend on the tests passing first.
    assert jobs["rotation-report"]["needs"] == "unit-tests"


def test_jobs_checkout_and_run_the_script_and_tests():
    jobs = _load_workflow()["jobs"]

    test_steps = jobs["unit-tests"]["steps"]
    assert any(s.get("uses", "").startswith("actions/checkout@v4") for s in test_steps)
    assert any("pytest tests/unit" in s.get("run", "") for s in test_steps)

    report_steps = jobs["rotation-report"]["steps"]
    assert any(s.get("uses", "").startswith("actions/checkout@v4") for s in report_steps)
    assert any("secret_rotation_validator.py" in s.get("run", "")
               for s in report_steps)


def test_workflow_references_existing_paths():
    text = WORKFLOW.read_text(encoding="utf-8")
    # Every file/dir the workflow names must actually exist in the repo.
    assert "secret_rotation_validator.py" in text
    assert (REPO / "secret_rotation_validator.py").is_file()
    assert "fixtures/secrets.json" in text
    assert (REPO / "fixtures" / "secrets.json").is_file()
    assert "tests/unit" in text
    assert (REPO / "tests" / "unit").is_dir()


def test_actionlint_passes_cleanly():
    actionlint = shutil.which("actionlint")
    if not actionlint:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        [actionlint, str(WORKFLOW)], capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "actionlint reported problems:\n" + result.stdout + result.stderr
    )
