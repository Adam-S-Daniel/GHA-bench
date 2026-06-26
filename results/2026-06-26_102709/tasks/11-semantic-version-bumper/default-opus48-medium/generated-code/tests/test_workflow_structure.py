"""Static checks on the workflow file: YAML structure, references, actionlint."""
import os
import shutil
import subprocess

import pytest

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML ships with most CI images
    yaml = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF = os.path.join(ROOT, ".github", "workflows", "semantic-version-bumper.yml")


@pytest.fixture(scope="module")
def wf():
    if yaml is None:
        pytest.skip("PyYAML not available")
    with open(WF, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.exists(WF)


def test_has_expected_triggers(wf):
    # PyYAML parses the bare `on:` key as the boolean True.
    triggers = wf.get(True, wf.get("on"))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_has_read_permissions(wf):
    assert wf["permissions"]["contents"] == "read"


def test_bump_job_steps_and_references(wf):
    steps = wf["jobs"]["bump"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses)
    assert any(u.startswith("actions/setup-python@") for u in uses)
    # The script must actually be invoked.
    runs = " ".join(s.get("run", "") for s in steps)
    assert "bump_version.py" in runs


def test_referenced_script_exists():
    assert os.path.exists(os.path.join(ROOT, "bump_version.py"))


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        ["actionlint", WF], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
