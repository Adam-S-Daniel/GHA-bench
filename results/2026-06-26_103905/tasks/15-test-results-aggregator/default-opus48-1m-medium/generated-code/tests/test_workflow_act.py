"""End-to-end workflow tests driven through `act` (nektos/act).

Per the task contract, the script is exercised ONLY through the GitHub Actions
pipeline -- never invoked directly here. For each test case we:

  1. Build a temp git repo containing the project files + that case's fixture
     data (the two fixture files the workflow consumes are overwritten).
  2. Run `act push --rm`, capturing stdout/stderr.
  3. Append the output to act-result.txt (a required artifact), delimited.
  4. Assert act exited 0, that every job reports "Job succeeded", and that the
     aggregated markdown contains the EXACT known-good numbers for that input.

There is also a set of static structure tests (YAML shape + actionlint) that do
not need Docker and always run.

`act` is slow (30-90s/run), so the suite uses at most three `act push` runs and
is skipped automatically when act/docker are unavailable.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

try:
    import yaml
except ImportError:  # pragma: no cover - yaml is stdlib-adjacent but optional
    yaml = None

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "test-results-aggregator.yml"
ACT_RESULT = ROOT / "act-result.txt"


# --------------------------------------------------------------------------- #
# Static workflow-structure tests (fast, no Docker)
# --------------------------------------------------------------------------- #

def test_workflow_file_exists():
    assert WORKFLOW.exists()


def test_referenced_script_paths_exist():
    """The workflow must reference files that actually exist in the repo."""
    text = WORKFLOW.read_text()
    assert "aggregator.py" in text
    assert (ROOT / "aggregator.py").exists()
    for fixture in ("fixtures/run1-junit.xml", "fixtures/run2-results.json"):
        assert fixture in text
        assert (ROOT / fixture).exists()


@pytest.mark.skipif(yaml is None, reason="pyyaml not installed")
def test_workflow_structure():
    spec = yaml.safe_load(WORKFLOW.read_text())
    # `on:` parses to the Python boolean True in YAML 1.1; accept either key.
    triggers = spec.get("on", spec.get(True))
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers

    assert spec["permissions"]["contents"] == "read"

    job = spec["jobs"]["aggregate"]
    assert job["runs-on"] == "ubuntu-latest"
    steps = job["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@") for u in uses)
    assert any(u.startswith("actions/setup-python@") for u in uses)
    # The aggregator must actually be invoked.
    runs = " ".join(s.get("run", "") for s in steps)
    assert "aggregator.py" in runs


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    result = subprocess.run(
        ["actionlint", str(WORKFLOW)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


# --------------------------------------------------------------------------- #
# act-driven end-to-end cases
# --------------------------------------------------------------------------- #

# Each case provides the contents of the two fixture files the workflow reads,
# plus the exact aggregated values we expect to see in the rendered markdown.
CASES = {
    # Default fixtures: token_refresh fails in xml run, passes in json run -> flaky.
    "default_flaky": {
        "xml": (ROOT / "fixtures" / "run1-junit.xml").read_text(),
        "json": (ROOT / "fixtures" / "run2-results.json").read_text(),
        "row": "| 12 | 9 | 1 | 2 | 6.69 |",
        "flaky": ["auth.tests.test_token_refresh"],
        "not_flaky": [],
        "status_marker": ":x: 1 test(s) failed",
    },
    # Everything green, identical across runs -> no flaky, status passing.
    "all_pass": {
        "xml": (
            '<?xml version="1.0"?>\n<testsuites><testsuite name="s" tests="2">'
            '<testcase classname="s" name="t1" time="1.0"/>'
            '<testcase classname="s" name="t2" time="2.0"/>'
            "</testsuite></testsuites>\n"
        ),
        "json": (
            '{"tests": ['
            '{"name": "t1", "classname": "s", "status": "passed", "duration": 1.0},'
            '{"name": "t2", "classname": "s", "status": "passed", "duration": 2.0}'
            "]}\n"
        ),
        "row": "| 4 | 4 | 0 | 0 | 6.00 |",
        "flaky": [],
        "not_flaky": ["s.t1", "s.t2"],
        "status_marker": "All tests passed",
    },
    # t_flaky fails then passes (flaky); t_broken fails in both runs (NOT flaky).
    "flaky_vs_consistent": {
        "xml": (
            '<?xml version="1.0"?>\n<testsuites><testsuite name="s" tests="2">'
            '<testcase classname="s" name="t_flaky" time="0.50">'
            "<failure>boom</failure></testcase>"
            '<testcase classname="s" name="t_broken" time="0.50">'
            "<failure>boom</failure></testcase>"
            "</testsuite></testsuites>\n"
        ),
        "json": (
            '{"tests": ['
            '{"name": "t_flaky", "classname": "s", "status": "passed", "duration": 0.5},'
            '{"name": "t_broken", "classname": "s", "status": "failed", "duration": 0.5}'
            "]}\n"
        ),
        "row": "| 4 | 1 | 3 | 0 | 2.00 |",
        "flaky": ["s.t_flaky"],
        "not_flaky": ["s.t_broken"],
        "status_marker": ":x: 3 test(s) failed",
    },
}


def _have_act() -> bool:
    return shutil.which("act") is not None and shutil.which("docker") is not None


def _build_repo(dest: Path, xml: str, json_text: str) -> None:
    """Materialise a self-contained git repo for one act run."""
    (dest / "fixtures").mkdir(parents=True, exist_ok=True)
    (dest / "tests").mkdir(parents=True, exist_ok=True)
    (dest / ".github" / "workflows").mkdir(parents=True, exist_ok=True)

    shutil.copy(ROOT / "aggregator.py", dest / "aggregator.py")
    shutil.copy(WORKFLOW, dest / ".github" / "workflows" / WORKFLOW.name)
    shutil.copy(ROOT / "tests" / "test_aggregator.py", dest / "tests" / "test_aggregator.py")
    if (ROOT / ".actrc").exists():
        shutil.copy(ROOT / ".actrc", dest / ".actrc")

    (dest / "fixtures" / "run1-junit.xml").write_text(xml)
    (dest / "fixtures" / "run2-results.json").write_text(json_text)

    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    subprocess.run(["git", "init", "-q"], cwd=dest, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=dest, check=True, env=env)
    subprocess.run(["git", "commit", "-q", "-m", "case"], cwd=dest, check=True, env=env)


def _run_act(dest: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=dest, capture_output=True, text=True, timeout=600)


@pytest.fixture(scope="module")
def act_outputs(tmp_path_factory):
    """Run act once per case and return {case_name: (proc, output_text)}."""
    if not _have_act():
        pytest.skip("act/docker not available")

    # Start the artifact file fresh for this run.
    ACT_RESULT.write_text("")
    outputs = {}
    for name, case in CASES.items():
        dest = tmp_path_factory.mktemp(name)
        _build_repo(dest, case["xml"], case["json"])
        proc = _run_act(dest)
        combined = proc.stdout + "\n" + proc.stderr
        with ACT_RESULT.open("a") as fh:
            fh.write(f"\n{'=' * 70}\nCASE: {name}\n{'=' * 70}\n")
            fh.write(combined)
            fh.write(f"\n[exit code: {proc.returncode}]\n")
        outputs[name] = (proc, combined)
    return outputs


@pytest.mark.parametrize("case_name", list(CASES))
def test_act_case(act_outputs, case_name):
    proc, out = act_outputs[case_name]
    case = CASES[case_name]

    assert proc.returncode == 0, f"act failed for {case_name}:\n{out}"
    assert "Job succeeded" in out, f"no 'Job succeeded' for {case_name}"

    # Exact totals row.
    assert case["row"] in out, f"expected row {case['row']!r} not in output"

    # Exact status verdict.
    assert case["status_marker"] in out

    # Flaky detection: every expected flaky id present, none of the consistent ones.
    flaky_section = out.split("Flaky Tests", 1)[1] if "Flaky Tests" in out else ""
    for fid in case["flaky"]:
        assert fid in flaky_section, f"{fid} should be flaky in {case_name}"
    if not case["flaky"]:
        assert "No flaky tests detected" in out
    for fid in case["not_flaky"]:
        assert fid not in flaky_section, f"{fid} must NOT be flaky in {case_name}"


def test_act_result_artifact_exists(act_outputs):
    assert ACT_RESULT.exists()
    assert ACT_RESULT.stat().st_size > 0
