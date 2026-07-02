"""
Structural tests for the GitHub Actions workflow itself: valid YAML,
expected triggers/jobs, correct script references, and a clean
actionlint run. These complement test_matrix_generator.py, which covers
the Python logic; act (invoked separately) covers actual execution.
"""
import os
import shutil
import subprocess

import yaml

WORKFLOW_PATH = ".github/workflows/environment-matrix-generator.yml"


def load_workflow():
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_has_expected_triggers():
    wf = load_workflow()
    # YAML parses bare 'on:' key as True in PyYAML's default loader.
    triggers = wf.get(True) or wf.get("on")
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_expected_jobs_and_dependency():
    wf = load_workflow()
    jobs = wf["jobs"]
    assert "unit-tests" in jobs
    assert "generate-matrix" in jobs
    assert jobs["generate-matrix"]["needs"] == "unit-tests"


def test_workflow_references_existing_script_and_fixtures():
    wf = load_workflow()
    steps = wf["jobs"]["generate-matrix"]["steps"]
    combined_run = "\n".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in combined_run
    assert os.path.isfile("matrix_generator.py")
    for fixture in ("fixtures/basic.json", "fixtures/exclude_include.json", "fixtures/too_large.json"):
        assert fixture in combined_run
        assert os.path.isfile(fixture)


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    assert actionlint is not None, "actionlint must be installed"
    result = subprocess.run([actionlint, WORKFLOW_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
