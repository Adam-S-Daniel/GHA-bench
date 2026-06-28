"""
Workflow structure tests.

These verify the GitHub Actions workflow file is well-formed *as configuration*:
correct triggers/jobs/steps, that it references files that actually exist, and
that it passes ``actionlint``. They run quickly (no Docker) and are part of the
main pytest suite. End-to-end execution is covered separately by
``run_act_tests.py`` (which drives the workflow through ``act``).
"""

import os
import shutil
import subprocess

import pytest
import yaml

WORKFLOW = ".github/workflows/pr-label-assigner.yml"


@pytest.fixture(scope="module")
def wf():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(wf):
    # YAML 1.1 (PyYAML) parses the bare key ``on`` as the boolean True, so the
    # triggers may live under either key depending on the parser.
    return wf.get("on", wf.get(True))


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW)


def test_has_expected_triggers(wf):
    triggers = _triggers(wf)
    assert triggers is not None, "workflow has no 'on:' triggers"
    assert "pull_request" in triggers
    assert "push" in triggers
    assert "workflow_dispatch" in triggers


def test_has_permissions(wf):
    perms = wf.get("permissions")
    assert isinstance(perms, dict)
    assert perms.get("contents") == "read"
    assert perms.get("pull-requests") == "write"


def test_has_env_defaults(wf):
    env = wf.get("env", {})
    assert env.get("CONFIG_FILE") == "label-rules.json"
    assert env.get("CHANGED_FILES_FILE") == "fixtures/changed-files.txt"


def test_jobs_and_dependency(wf):
    jobs = wf["jobs"]
    assert "assign-labels" in jobs
    assert "report" in jobs
    # The report job must depend on the compute job.
    assert jobs["report"]["needs"] == "assign-labels"


def test_job_exposes_labels_output(wf):
    outputs = wf["jobs"]["assign-labels"].get("outputs", {})
    assert "labels" in outputs


def test_uses_checkout_v4(wf):
    steps = wf["jobs"]["assign-labels"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert "actions/checkout@v4" in uses


def test_workflow_invokes_the_script(wf):
    steps = wf["jobs"]["assign-labels"]["steps"]
    run_blocks = "\n".join(s.get("run", "") for s in steps)
    assert "pr_label_assigner.py" in run_blocks


def test_referenced_files_exist():
    # Every file the workflow relies on must be present in the repo.
    for path in (
        "pr_label_assigner.py",
        "label-rules.json",
        "fixtures/changed-files.txt",
    ):
        assert os.path.isfile(path), f"workflow references missing file: {path}"


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    assert actionlint, "actionlint must be installed"
    result = subprocess.run(
        [actionlint, WORKFLOW],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
