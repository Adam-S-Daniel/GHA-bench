"""
Structural tests for the GitHub Actions workflow file itself (not the act
run, which is covered by run_act_tests.py). These check the YAML shape and
that actionlint passes, without needing Docker.
"""
import subprocess
import os
import yaml

WORKFLOW_PATH = ".github/workflows/artifact-cleanup-script.yml"


def load_workflow():
    with open(WORKFLOW_PATH) as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_has_expected_triggers():
    wf = load_workflow()
    # YAML parses the bare key `on` as boolean True
    triggers = wf.get("on") or wf.get(True)
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_test_and_cleanup_jobs_with_dependency():
    wf = load_workflow()
    jobs = wf["jobs"]
    assert "test" in jobs
    assert "cleanup" in jobs
    assert jobs["cleanup"]["needs"] == "test"


def test_workflow_permissions_are_scoped():
    wf = load_workflow()
    assert wf["permissions"]["contents"] == "read"


def test_workflow_references_existing_script_and_fixtures():
    wf = load_workflow()
    steps_text = yaml.dump(wf["jobs"]["cleanup"]["steps"])
    assert os.path.isfile("artifact_cleanup.py")
    assert "artifact_cleanup.py" in steps_text

    # Fixture paths are supplied per-matrix-case rather than hardcoded in the
    # step; verify each fixture referenced by the matrix actually exists.
    matrix_cases = wf["jobs"]["cleanup"]["strategy"]["matrix"]["case"]
    for case in matrix_cases:
        assert os.path.isfile(case["data"])

    test_steps_text = yaml.dump(wf["jobs"]["test"]["steps"])
    assert os.path.isfile("test_artifact_cleanup.py")
    assert "test_artifact_cleanup.py" in test_steps_text


def test_workflow_cleanup_job_uses_matrix_with_two_cases():
    wf = load_workflow()
    matrix_cases = wf["jobs"]["cleanup"]["strategy"]["matrix"]["case"]
    assert len(matrix_cases) == 2
    names = {c["name"] for c in matrix_cases}
    assert names == {"age-and-count-policy", "size-budget-policy"}


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", WORKFLOW_PATH], capture_output=True, text=True
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
