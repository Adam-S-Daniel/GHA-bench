"""Structural tests for .github/workflows/artifact-cleanup-script.yml.

These validate the workflow file itself (triggers, jobs, references,
actionlint cleanliness) and are run locally with `pytest`, independent of
the act-based functional pipeline tests in run-act-tests.sh.
"""
import subprocess
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "artifact-cleanup-script.yml"


def load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file(), f"Workflow file missing: {WORKFLOW_PATH}"


def test_workflow_parses_as_valid_yaml():
    doc = load_workflow()
    assert isinstance(doc, dict)


def test_workflow_has_expected_triggers():
    doc = load_workflow()
    # PyYAML parses the bare `on:` key as boolean True, not the string "on".
    triggers = doc.get("on", doc.get(True))
    assert triggers is not None, "Workflow is missing an 'on:' trigger section"
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers
    assert triggers["schedule"][0]["cron"] == "0 3 * * *"


def test_workflow_has_expected_jobs_and_dependency():
    doc = load_workflow()
    jobs = doc["jobs"]
    assert "test" in jobs
    assert "cleanup" in jobs
    assert jobs["cleanup"]["needs"] == "test"


def test_workflow_declares_minimal_permissions():
    doc = load_workflow()
    assert doc["permissions"]["contents"] == "read"


def test_workflow_defines_config_path_env_var():
    doc = load_workflow()
    assert doc["env"]["ARTIFACT_CONFIG_PATH"] == "fixtures/artifacts.json"


def test_jobs_use_checkout_v4():
    doc = load_workflow()
    for job_name, job in doc["jobs"].items():
        uses_checkout = any(
            step.get("uses", "").startswith("actions/checkout@v4")
            for step in job["steps"]
        )
        assert uses_checkout, f"Job '{job_name}' does not check out the repo with actions/checkout@v4"


def test_run_steps_use_pwsh_shell():
    doc = load_workflow()
    for job_name, job in doc["jobs"].items():
        for step in job["steps"]:
            if "run" in step:
                assert step.get("shell") == "pwsh", (
                    f"Job '{job_name}' step '{step.get('name')}' runs a script "
                    "but does not declare shell: pwsh"
                )


def test_workflow_references_existing_script_files():
    doc = load_workflow()
    cleanup_job = doc["jobs"]["cleanup"]
    run_steps_text = "\n".join(step.get("run", "") for step in cleanup_job["steps"])
    assert "./src/run-cleanup.ps1" in run_steps_text
    assert (REPO_ROOT / "src" / "run-cleanup.ps1").is_file()
    assert (REPO_ROOT / "src" / "ArtifactCleanup.psm1").is_file()

    test_job = doc["jobs"]["test"]
    test_run_steps_text = "\n".join(step.get("run", "") for step in test_job["steps"])
    assert "./tests" in test_run_steps_text
    assert (REPO_ROOT / "tests").is_dir()
    assert any((REPO_ROOT / "tests").glob("*.Tests.ps1"))


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW_PATH)],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
