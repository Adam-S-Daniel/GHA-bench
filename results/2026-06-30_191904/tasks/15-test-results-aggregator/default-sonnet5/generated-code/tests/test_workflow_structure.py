"""
Workflow structure tests.

These tests check the *shape* of the GitHub Actions workflow file and its
references (YAML structure, triggers, jobs, script paths, actionlint) without
actually executing the workflow. Execution/behavioral verification happens
separately through `act` in tests/test_act_pipeline.py, per the task
requirement that functional testing of the aggregator must go through the
real CI pipeline rather than calling the script's functions directly.
"""
import os
import subprocess

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "test-results-aggregator.yml")


def test_workflow_file_exists():
    """The workflow file must exist at the required path."""
    assert os.path.isfile(WORKFLOW_PATH), f"Expected workflow file at {WORKFLOW_PATH}"


def _load_workflow() -> dict:
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_is_valid_yaml():
    """The file must parse as valid YAML."""
    doc = _load_workflow()
    assert isinstance(doc, dict)


def test_workflow_has_required_triggers():
    """Must declare push, pull_request, workflow_dispatch, and schedule triggers."""
    doc = _load_workflow()
    # PyYAML parses the bare `on:` key as the boolean True in YAML 1.1;
    # GitHub Actions workflows always use `on` as a literal key, so handle
    # both the string and boolean-key forms defensively.
    triggers = doc.get("on", doc.get(True))
    assert triggers is not None, "workflow is missing an 'on:' trigger block"
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_permissions_block():
    """Must declare an explicit (least-privilege) permissions block."""
    doc = _load_workflow()
    assert "permissions" in doc
    assert doc["permissions"].get("contents") == "read"


def test_workflow_has_env_vars():
    """Must declare workflow-level environment variables."""
    doc = _load_workflow()
    assert "env" in doc
    assert "FIXTURES_DIR" in doc["env"]


def test_workflow_has_expected_jobs_with_dependency():
    """Must have an aggregate job and a status-reporting job that depends on it."""
    doc = _load_workflow()
    jobs = doc["jobs"]
    assert "aggregate-results" in jobs
    assert "report-status" in jobs
    assert jobs["report-status"]["needs"] == "aggregate-results"


def test_workflow_uses_checkout_action():
    doc = _load_workflow()
    steps = doc["jobs"]["aggregate-results"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@") for u in uses)


def test_workflow_references_aggregator_script():
    """The workflow must invoke aggregator.py, and that file must exist."""
    doc = _load_workflow()
    steps = doc["jobs"]["aggregate-results"]["steps"]
    run_blocks = "\n".join(s.get("run", "") for s in steps)
    assert "aggregator.py" in run_blocks
    script_path = os.path.join(REPO_ROOT, "aggregator.py")
    assert os.path.isfile(script_path), f"Referenced script missing: {script_path}"


def test_workflow_references_existing_fixtures_dir():
    """The FIXTURES_DIR env default must point at a directory that exists
    and contains at least one .xml and one .json fixture, matching the
    globs used in the 'Run aggregator' step."""
    doc = _load_workflow()
    fixtures_dir = doc["env"]["FIXTURES_DIR"]
    abs_dir = os.path.join(REPO_ROOT, fixtures_dir)
    assert os.path.isdir(abs_dir), f"FIXTURES_DIR does not exist: {abs_dir}"
    entries = os.listdir(abs_dir)
    assert any(f.endswith(".xml") for f in entries)
    assert any(f.endswith(".json") for f in entries)


def test_actionlint_passes():
    """actionlint must validate the workflow file with no errors."""
    result = subprocess.run(
        ["actionlint", WORKFLOW_PATH],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"actionlint failed (exit {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
