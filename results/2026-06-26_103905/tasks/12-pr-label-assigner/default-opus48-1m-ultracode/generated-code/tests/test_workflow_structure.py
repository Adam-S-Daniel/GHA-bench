"""Workflow structure tests (part of the main suite).

These assert that the GitHub Actions workflow:
  * parses as YAML and has the expected triggers / jobs / steps,
  * references script + config files that actually exist on disk,
  * passes ``actionlint`` (exit code 0).

Note the classic GitHub Actions YAML gotcha: the bare key ``on`` is parsed by
PyYAML (YAML 1.1) as the boolean ``True``, so we look it up under both keys.
"""

import os
import shutil
import subprocess

import pytest
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "pr-label-assigner.yml")


@pytest.fixture(scope="module")
def wf():
    with open(WORKFLOW, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(wf):
    # 'on' may have been parsed as the boolean True (YAML 1.1).
    on = wf.get("on", wf.get(True))
    assert on is not None, "workflow has no 'on' triggers"
    return on


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW)


def test_workflow_name(wf):
    assert wf["name"] == "PR Label Assigner"


def test_expected_triggers(wf):
    triggers = _triggers(wf)
    # Mapping form: keys are the event names.
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers


def test_permissions_present(wf):
    perms = wf["permissions"]
    assert perms["contents"] == "read"
    assert perms["pull-requests"] == "write"


def test_env_points_at_existing_files(wf):
    env = wf["env"]
    assert os.path.isfile(os.path.join(ROOT, env["CONFIG_FILE"]))
    assert os.path.isfile(os.path.join(ROOT, env["CHANGED_FILES_FILE"]))


def test_job_and_runner(wf):
    job = wf["jobs"]["assign-labels"]
    assert job["runs-on"] == "ubuntu-latest"


def test_steps_checkout_and_run_script(wf):
    steps = wf["jobs"]["assign-labels"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert "actions/checkout@v4" in uses, "must check out the repo"

    runs = "\n".join(s.get("run", "") for s in steps)
    # The workflow must invoke our actual script.
    assert "pr_label_assigner.py" in runs
    assert os.path.isfile(os.path.join(ROOT, "pr_label_assigner.py"))


def test_assign_step_has_id_for_outputs(wf):
    steps = wf["jobs"]["assign-labels"]["steps"]
    assign = [s for s in steps if s.get("id") == "assign"]
    assert assign, "the labeling step needs id: assign for step outputs"


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    proc = subprocess.run(
        ["actionlint", WORKFLOW],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
