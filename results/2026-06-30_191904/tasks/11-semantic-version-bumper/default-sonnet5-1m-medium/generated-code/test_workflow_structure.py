"""
Static structure tests for the GitHub Actions workflow itself: valid YAML,
expected triggers/jobs/steps, correct references to the script and fixture
files on disk, and a clean actionlint run. These check the *shape* of the
pipeline; the actual runtime behavior of the pipeline is verified separately
by act_test_harness.py, which executes the workflow through `act`.
"""
import os
import shutil
import subprocess

import yaml

REPO_ROOT = os.path.dirname(__file__)
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "semantic-version-bumper.yml")


def _load_workflow():
    with open(WORKFLOW_PATH) as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_is_valid_yaml_with_expected_triggers():
    workflow = _load_workflow()
    # PyYAML parses the bare `on:` key as boolean True, so check both spellings.
    triggers = workflow.get("on", workflow.get(True))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_bump_version_job_with_matrix_of_three_cases():
    workflow = _load_workflow()
    jobs = workflow["jobs"]
    assert "bump-version" in jobs
    job = jobs["bump-version"]
    assert job["runs-on"] == "ubuntu-latest"
    cases = job["strategy"]["matrix"]["case"]
    assert len(cases) == 3
    assert {c["name"] for c in cases} == {"patch", "minor", "major"}


def test_workflow_declares_read_only_permissions():
    workflow = _load_workflow()
    assert workflow["permissions"] == {"contents": "read"}


def test_workflow_steps_use_pinned_actions():
    workflow = _load_workflow()
    steps = workflow["jobs"]["bump-version"]["steps"]
    uses = [s["uses"] for s in steps if "uses" in s]
    assert "actions/checkout@v4" in uses
    assert any(u.startswith("actions/setup-python@") for u in uses)


def test_workflow_references_existing_script_and_fixture_files():
    workflow = _load_workflow()
    steps = workflow["jobs"]["bump-version"]["steps"]
    run_text = "\n".join(s["run"] for s in steps if "run" in s)

    assert "version_bumper.py" in run_text
    assert os.path.isfile(os.path.join(REPO_ROOT, "version_bumper.py"))

    matrix_cases = workflow["jobs"]["bump-version"]["strategy"]["matrix"]["case"]
    for case in matrix_cases:
        fixture_path = os.path.join(REPO_ROOT, case["commits_fixture"])
        assert os.path.isfile(fixture_path), f"missing fixture referenced by workflow: {fixture_path}"

    assert os.path.isfile(os.path.join(REPO_ROOT, "fixtures", "version_1.0.0.txt"))


def test_actionlint_passes_on_workflow():
    actionlint = shutil.which("actionlint")
    assert actionlint is not None, "actionlint must be installed"
    result = subprocess.run([actionlint, WORKFLOW_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
