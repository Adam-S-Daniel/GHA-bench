"""Static checks on the GitHub Actions workflow file.

These do NOT run Docker; they validate that the workflow is well-formed, wired
to the right script/config paths, and passes actionlint.
"""
import os
import subprocess

import pytest

yaml = pytest.importorskip("yaml")

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(HERE, ".github", "workflows", "secret-rotation-validator.yml")


def _load():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW)


def test_has_expected_triggers():
    wf = _load()
    # PyYAML parses the bare `on:` key as the boolean True.
    triggers = wf.get(True, wf.get("on"))
    assert set(["push", "pull_request", "schedule", "workflow_dispatch"]).issubset(triggers)


def test_has_jobs_and_dependency():
    wf = _load()
    assert "validate" in wf["jobs"]
    assert "gate" in wf["jobs"]
    assert wf["jobs"]["gate"]["needs"] == "validate"


def test_permissions_least_privilege():
    wf = _load()
    assert wf["permissions"]["contents"] == "read"


def test_references_existing_script_and_config():
    wf = _load()
    text = open(WORKFLOW, encoding="utf-8").read()
    assert "secret_rotation_validator.py" in text
    assert os.path.isfile(os.path.join(HERE, "secret_rotation_validator.py"))
    # CONFIG_PATH env points at a real fixture.
    config_rel = wf["env"]["CONFIG_PATH"]
    assert os.path.isfile(os.path.join(HERE, config_rel))


def test_uses_pinned_actions():
    text = open(WORKFLOW, encoding="utf-8").read()
    assert "actions/checkout@v4" in text
    assert "actions/setup-python@v5" in text


def test_actionlint_passes():
    proc = subprocess.run(
        ["actionlint", WORKFLOW], capture_output=True, text=True
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
