"""
Pipeline tests: every matrix case is exercised *through the GitHub Actions
workflow* via `act` (nektos/act) running in Docker -- not by calling the script
directly. This is the authoritative acceptance suite required by the task.

For each test case we:
  1. Build a throwaway git repo containing the project files + that case's
     fixture data (copied to ``matrix-config.json``).
  2. Run ``act push --rm`` and capture the full output.
  3. Append the output to ``act-result.txt`` (a required artifact), delimited.
  4. Assert act exited 0, every job shows "Job succeeded", and the workflow
     emitted the EXACT expected matrix (size, combinations, max-parallel,
     fail-fast) for that input.

This file also contains static workflow-structure tests (YAML shape, script
references, actionlint) that run without Docker.
"""

import json
import os
import shutil
import subprocess
import tempfile

import pytest
import yaml

# Project root = parent of this tests/ directory.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "environment-matrix-generator.yml")
ACT_RESULT = os.path.join(ROOT, "act-result.txt")
ACT_IMAGE = "act-ubuntu-pwsh:latest"

HAVE_ACT = shutil.which("act") is not None
HAVE_DOCKER = shutil.which("docker") is not None


# ---------------------------------------------------------------------------
# Expected values per test case -- known-good results for each fixture input.
# ---------------------------------------------------------------------------

CASES = [
    {
        "name": "basic",
        "fixture": "basic.json",
        "size": 4,
        "include": [
            {"os": "ubuntu-latest", "version": "3.11"},
            {"os": "ubuntu-latest", "version": "3.12"},
            {"os": "windows-latest", "version": "3.11"},
            {"os": "windows-latest", "version": "3.12"},
        ],
        "max_parallel": "2",
        "fail_fast": "false",
    },
    {
        "name": "include-exclude",
        "fixture": "include-exclude.json",
        "size": 5,
        "include": [
            {"os": "ubuntu-latest", "version": "3.11", "coverage": True},
            {"os": "ubuntu-latest", "version": "3.12"},
            {"os": "windows-latest", "version": "3.11"},
            {"os": "macos-latest", "version": "3.12"},
            {"os": "ubuntu-latest", "version": "3.13", "experimental": True},
        ],
        "max_parallel": "3",
        "fail_fast": "true",
    },
    {
        "name": "flags",
        "fixture": "flags.json",
        "size": 3,
        "include": [
            {"os": "ubuntu-latest", "version": "3.12", "feature": "minimal"},
            {"os": "ubuntu-latest", "version": "3.12", "feature": "default"},
            {"os": "ubuntu-latest", "version": "3.12", "feature": "full"},
        ],
        "max_parallel": "1",
        "fail_fast": "false",
    },
]


# ---------------------------------------------------------------------------
# Static workflow-structure tests (no Docker needed)
# ---------------------------------------------------------------------------

def _load_workflow():
    with open(WORKFLOW, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(wf):
    # PyYAML parses the bare key ``on`` as the boolean True (YAML 1.1), so look
    # under both spellings.
    return wf["on"] if "on" in wf else wf[True]


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW), f"workflow missing: {WORKFLOW}"


def test_workflow_has_expected_triggers():
    triggers = _triggers(_load_workflow())
    for event in ("push", "pull_request", "workflow_dispatch", "schedule"):
        assert event in triggers, f"missing trigger: {event}"


def test_workflow_has_permissions_and_env():
    wf = _load_workflow()
    assert wf.get("permissions", {}).get("contents") == "read"
    assert "MATRIX_CONFIG" in wf.get("env", {})


def test_workflow_jobs_and_dependency():
    wf = _load_workflow()
    jobs = wf["jobs"]
    assert "generate-matrix" in jobs
    assert "build" in jobs
    # build depends on generate-matrix (job dependency).
    assert jobs["build"]["needs"] == "generate-matrix"
    # generate-matrix exposes the matrix output.
    assert "matrix" in jobs["generate-matrix"]["outputs"]


def test_workflow_checks_out_and_runs_script():
    wf = _load_workflow()
    steps = wf["jobs"]["generate-matrix"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses), "needs checkout@v4"
    runs = " ".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in runs, "workflow must invoke the script"


def test_workflow_consumes_matrix_via_fromjson():
    wf = _load_workflow()
    strat = wf["jobs"]["build"]["strategy"]
    # The matrix is dynamic, sourced from the generate-matrix job output.
    assert "fromJSON(needs.generate-matrix.outputs.matrix)" in str(strat["matrix"])


def test_referenced_script_paths_exist():
    # Every script the workflow references must actually be present.
    assert os.path.isfile(os.path.join(ROOT, "matrix_generator.py"))
    assert os.path.isfile(os.path.join(ROOT, "matrix-config.json"))


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    proc = subprocess.run(
        ["actionlint", WORKFLOW],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


# ---------------------------------------------------------------------------
# act execution tests -- the real pipeline run
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module", autouse=True)
def _reset_act_result():
    """Truncate the shared act-result.txt artifact once per module run."""
    with open(ACT_RESULT, "w", encoding="utf-8") as fh:
        fh.write("# act-result.txt -- captured output of every workflow run\n")
    yield


def _setup_repo(workdir, fixture_name):
    """Create a temp git repo with project files + the case's fixture data."""
    os.makedirs(os.path.join(workdir, ".github", "workflows"), exist_ok=True)
    shutil.copy(os.path.join(ROOT, "matrix_generator.py"), workdir)
    shutil.copy(WORKFLOW, os.path.join(workdir, ".github", "workflows"))
    # Reuse the prebuilt act image mapping if the workspace provides one.
    actrc = os.path.join(ROOT, ".actrc")
    if os.path.isfile(actrc):
        shutil.copy(actrc, workdir)
    # The case's fixture becomes the config the workflow reads by default.
    shutil.copy(
        os.path.join(ROOT, "tests", "fixtures", fixture_name),
        os.path.join(workdir, "matrix-config.json"),
    )
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    subprocess.run(["git", "init", "-q"], cwd=workdir, check=True, env=env)
    subprocess.run(["git", "config", "user.email", "ci@example.com"], cwd=workdir, check=True)
    subprocess.run(["git", "config", "user.name", "ci"], cwd=workdir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=workdir, check=True)
    subprocess.run(["git", "commit", "-qm", "test fixture"], cwd=workdir, check=True, env=env)


def _run_act(workdir):
    """Run the workflow via act push; return (exit_code, combined_output)."""
    cmd = [
        "act", "push", "--rm",
        "--pull=false",                 # use the locally built image, never pull
        "-P", f"ubuntu-latest={ACT_IMAGE}",
    ]
    proc = subprocess.run(
        cmd, cwd=workdir, capture_output=True, text=True, timeout=600
    )
    return proc.returncode, proc.stdout + proc.stderr


def _append_result(case_name, exit_code, output):
    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write("\n" + "=" * 72 + "\n")
        fh.write(f"TEST CASE: {case_name}    (act exit code: {exit_code})\n")
        fh.write("=" * 72 + "\n")
        fh.write(output)
        if not output.endswith("\n"):
            fh.write("\n")


def _marker(output, key):
    """Extract the value after ``<key>=`` from an act-prefixed log line."""
    for line in output.splitlines():
        if f"{key}=" in line:
            return line.split(f"{key}=", 1)[1].strip()
    return None


@pytest.mark.skipif(not (HAVE_ACT and HAVE_DOCKER), reason="act/docker required")
@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_workflow_runs_through_act(case):
    workdir = tempfile.mkdtemp(prefix=f"act-{case['name']}-")
    try:
        _setup_repo(workdir, case["fixture"])
        exit_code, output = _run_act(workdir)
    finally:
        # Always record the output, even on failure, so act-result.txt is
        # complete and debuggable.
        pass
    _append_result(case["name"], exit_code, output)
    shutil.rmtree(workdir, ignore_errors=True)

    # 1. act must succeed.
    assert exit_code == 0, f"act exited {exit_code} for {case['name']}:\n{output[-2000:]}"

    # 2. Every job must report success and none may fail.
    assert "Job failed" not in output, f"a job failed for {case['name']}"
    succeeded = output.count("Job succeeded")
    expected_jobs = 1 + case["size"]  # generate-matrix + one build leg per combo
    assert succeeded == expected_jobs, (
        f"{case['name']}: expected {expected_jobs} successful jobs, "
        f"saw {succeeded}"
    )

    # 3. Exact-value assertions on the generated matrix.
    assert _marker(output, "MATRIX_SIZE") == str(case["size"])
    assert _marker(output, "MAX_PARALLEL") == case["max_parallel"]
    assert _marker(output, "FAIL_FAST") == case["fail_fast"]

    matrix_json = _marker(output, "MATRIX_JSON")
    assert matrix_json is not None, "MATRIX_JSON marker not found in act output"
    parsed = json.loads(matrix_json)
    assert parsed["include"] == case["include"], (
        f"{case['name']}: matrix mismatch\n"
        f"  expected: {case['include']}\n  got:      {parsed['include']}"
    )


def test_act_result_artifact_exists():
    # The required artifact must exist on disk when the suite finishes.
    assert os.path.isfile(ACT_RESULT), "act-result.txt was not produced"
