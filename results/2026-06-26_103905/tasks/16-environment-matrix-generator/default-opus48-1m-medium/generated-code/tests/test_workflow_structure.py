"""Workflow structure + act-result validation tests.

These do NOT invoke act (that is run_act_tests.py's job); they validate the
workflow file's structure, that it references real script paths, that
actionlint passes, and -- once act-result.txt exists -- that the captured act
output asserts the exact expected values.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"
ACT_RESULT = ROOT / "act-result.txt"


def _load_yaml():
    import yaml  # PyYAML

    return yaml.safe_load(WORKFLOW.read_text())


# --------------------------------------------------------------------------- #
# Structure
# --------------------------------------------------------------------------- #
def test_workflow_file_exists():
    assert WORKFLOW.is_file()


def test_workflow_triggers():
    wf = _load_yaml()
    # PyYAML parses the bare `on:` key as boolean True.
    triggers = wf.get("on", wf.get(True))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_permissions_least_privilege():
    wf = _load_yaml()
    assert wf["permissions"]["contents"] == "read"


def test_workflow_jobs_and_dependency():
    wf = _load_yaml()
    jobs = wf["jobs"]
    assert "generate" in jobs and "build" in jobs
    # build depends on generate (job dependency requirement)
    assert jobs["build"]["needs"] == "generate"
    # dynamic matrix consumes the generate output
    assert "fromJSON(needs.generate.outputs.matrix)" in json.dumps(
        jobs["build"]["strategy"]
    )


def test_workflow_references_real_paths():
    text = WORKFLOW.read_text()
    assert "matrix_generator.py" in text
    assert (ROOT / "matrix_generator.py").is_file()
    # Every fixture the workflow names must exist on disk.
    for name in re.findall(r"fixtures/([\w.-]+\.json)", text):
        assert (ROOT / "fixtures" / name).is_file(), name


def test_workflow_uses_checkout_and_python():
    text = WORKFLOW.read_text()
    assert "actions/checkout@v4" in text
    # The generator has no third-party deps; it runs on the runner's system
    # python3 (preinstalled on ubuntu-latest).
    assert "python3" in text


# --------------------------------------------------------------------------- #
# actionlint
# --------------------------------------------------------------------------- #
@pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
def test_actionlint_passes():
    proc = subprocess.run(
        ["actionlint", str(WORKFLOW)], capture_output=True, text=True
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr


# --------------------------------------------------------------------------- #
# act-result.txt validation (only when the artifact exists)
# --------------------------------------------------------------------------- #
PREFIX_RE = re.compile(r"^\[[^\]]*\]\s*(?:\|\s?)?")


def _strip(line):
    return PREFIX_RE.sub("", line).rstrip()


def _block(output, name):
    lines = [_strip(l) for l in output.splitlines()]
    start, end = f"===FIXTURE: {name}===", f"===END FIXTURE: {name}==="
    i = lines.index(start)
    j = lines.index(end, i)
    return lines[i + 1 : j]


@pytest.mark.skipif(not ACT_RESULT.exists(), reason="act-result.txt not generated yet")
def test_act_result_exact_values():
    output = ACT_RESULT.read_text()
    assert "exit code: 0" in output, "act must have exited 0"
    assert output.count("Job succeeded") >= 5

    for name in ["primary", "exclude", "include", "features"]:
        expected = json.loads((ROOT / "fixtures" / f"{name}.expected.txt").read_text())
        parsed = next(
            json.loads(l.strip())
            for l in _block(output, name)
            if l.strip().startswith("{")
        )
        assert parsed == expected, f"{name} mismatch"

    assert "exceeds the configured max_size of 10" in output
    assert "os=ubuntu-latest" in output
    assert "os=windows-latest" in output
