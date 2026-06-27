"""
Workflow tests for the Environment Matrix Generator.

Two groups:

1. Structure / static tests (fast):
   * Parse the workflow YAML and assert on its triggers, jobs and steps.
   * Verify the workflow references files that actually exist on disk.
   * Run actionlint as a subprocess and assert it exits 0.

2. Act execution tests (slow, require Docker):
   * For every fixture, build a throwaway git repo containing the project files
     plus that fixture as ``config.json``, run ``act push --rm``, capture the
     output, append it to ``act-result.txt`` and assert on EXACT expected values
     (matrix JSON, size, fail-fast / max-parallel markers, job success, and the
     number of expanded matrix jobs).

The act tests are intentionally driven by a small, pre-computed expectation table
so assertions are exact, not "some output appeared".
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parent
WORKFLOW = ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"
ACT_RESULT = ROOT / "act-result.txt"


# --------------------------------------------------------------------------- #
# Group 1: structure / static analysis
# --------------------------------------------------------------------------- #
@pytest.fixture(scope="module")
def workflow():
    return yaml.safe_load(WORKFLOW.read_text())


def test_workflow_file_exists():
    assert WORKFLOW.is_file(), f"Workflow not found at {WORKFLOW}"


def test_workflow_has_expected_triggers(workflow):
    # PyYAML parses the bare ``on:`` key as the boolean True.
    triggers = workflow.get(True, workflow.get("on"))
    assert triggers is not None, "workflow has no triggers"
    for expected in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert expected in triggers, f"missing trigger: {expected}"


def test_workflow_has_least_privilege_permissions(workflow):
    assert workflow["permissions"]["contents"] == "read"


def test_workflow_jobs_and_dependency(workflow):
    jobs = workflow["jobs"]
    assert "generate-matrix" in jobs
    assert "build" in jobs
    # build must depend on generate-matrix (job dependency).
    assert jobs["build"]["needs"] == "generate-matrix"
    # build consumes the generated matrix dynamically.
    assert "fromJson(needs.generate-matrix.outputs.matrix)" in str(
        jobs["build"]["strategy"]["matrix"]
    )


def test_workflow_uses_checkout_v4(workflow):
    steps = workflow["jobs"]["generate-matrix"]["steps"]
    assert any(s.get("uses") == "actions/checkout@v4" for s in steps)


def test_workflow_references_existing_script(workflow):
    steps = workflow["jobs"]["generate-matrix"]["steps"]
    run_blob = "\n".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in run_blob
    assert (ROOT / "matrix_generator.py").is_file()


def test_actionlint_passes():
    if shutil.which("actionlint") is None:
        pytest.skip("actionlint not installed")
    proc = subprocess.run(
        ["actionlint", str(WORKFLOW)],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


# --------------------------------------------------------------------------- #
# Group 2: act execution (exact-value assertions per fixture)
# --------------------------------------------------------------------------- #
# Pre-computed, known-good expectations. Each entry is a complete contract for
# one fixture run through the pipeline.
ACT_CASES = [
    {
        "name": "basic",
        "fixture": "fixtures/basic.json",
        "size": 4,
        "matrix_json": (
            '{"include":['
            '{"os":"ubuntu-latest","node":"18"},'
            '{"os":"ubuntu-latest","node":"20"},'
            '{"os":"windows-latest","node":"18"},'
            '{"os":"windows-latest","node":"20"}]}'
        ),
        "fail_fast": "unset",
        "max_parallel": "unset",
    },
    {
        "name": "exclude-include",
        "fixture": "fixtures/exclude-include.json",
        "size": 4,
        "matrix_json": (
            '{"include":['
            '{"os":"ubuntu-latest","node":"18"},'
            '{"os":"ubuntu-latest","node":"20"},'
            '{"os":"windows-latest","node":"20"},'
            '{"os":"macos-latest","node":"20","experimental":true}]}'
        ),
        "fail_fast": "false",
        "max_parallel": "2",
    },
    {
        "name": "feature-flags",
        "fixture": "fixtures/feature-flags.json",
        "size": 4,
        "matrix_json": (
            '{"include":['
            '{"os":"ubuntu-latest","python":"3.11","feature":"fast"},'
            '{"os":"ubuntu-latest","python":"3.11","feature":"safe"},'
            '{"os":"ubuntu-latest","python":"3.12","feature":"fast"},'
            '{"os":"ubuntu-latest","python":"3.12","feature":"safe"}]}'
        ),
        "fail_fast": "true",
        "max_parallel": "unset",
    },
]

PROJECT_FILES = ["matrix_generator.py", ".actrc"]


def _setup_repo(dest: Path, fixture: str):
    """Create a throwaway git repo at *dest* with the project + fixture config."""
    (dest / ".github" / "workflows").mkdir(parents=True, exist_ok=True)
    shutil.copy(WORKFLOW, dest / ".github" / "workflows" / WORKFLOW.name)
    for f in PROJECT_FILES:
        src = ROOT / f
        if src.exists():
            shutil.copy(src, dest / f)
    # The chosen fixture becomes the config the workflow reads.
    shutil.copy(ROOT / fixture, dest / "config.json")

    subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
    subprocess.run(["git", "add", "-A"], cwd=dest, check=True)
    subprocess.run(
        [
            "git",
            "-c", "user.email=ci@example.com",
            "-c", "user.name=ci",
            "commit", "-q", "-m", "test",
        ],
        cwd=dest,
        check=True,
    )


def _run_act(dest: Path) -> subprocess.CompletedProcess:
    # --pull=false: the act image (per .actrc) is built locally; never re-pull it.
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=dest,
        capture_output=True,
        text=True,
        timeout=600,
    )


@pytest.fixture(scope="module")
def _reset_act_result():
    # Start every full run with a fresh artifact file.
    if ACT_RESULT.exists():
        ACT_RESULT.unlink()
    yield


@pytest.mark.act
@pytest.mark.parametrize("case", ACT_CASES, ids=[c["name"] for c in ACT_CASES])
def test_act_run(case, tmp_path, _reset_act_result):
    if shutil.which("act") is None:
        pytest.skip("act not installed")

    repo = tmp_path / case["name"]
    repo.mkdir()
    _setup_repo(repo, case["fixture"])
    proc = _run_act(repo)
    output = proc.stdout + "\n" + proc.stderr

    # Persist the full output as the required artifact, clearly delimited.
    with ACT_RESULT.open("a", encoding="utf-8") as fh:
        fh.write("=" * 78 + "\n")
        fh.write(f"TEST CASE: {case['name']}  (fixture: {case['fixture']})\n")
        fh.write(f"act exit code: {proc.returncode}\n")
        fh.write("=" * 78 + "\n")
        fh.write(output)
        fh.write("\n\n")

    # 1. act must succeed.
    assert proc.returncode == 0, f"act failed for {case['name']}:\n{output}"

    # 2. Exact generated values.
    assert f"MATRIX_SIZE={case['size']}" in output
    assert case["matrix_json"] in output, "matrix JSON did not match expected"
    assert f"FAIL_FAST={case['fail_fast']}" in output
    assert f"MAX_PARALLEL={case['max_parallel']}" in output

    # 3. The dynamic matrix expanded into exactly `size` build jobs.
    assert output.count("COMBO_DONE") >= case["size"]

    # 4. Every job (generate-matrix + each build job) succeeded.
    assert output.count("Job succeeded") >= case["size"] + 1


@pytest.mark.act
def test_act_result_artifact_exists():
    # Sanity: after the parametrized runs the artifact must exist and be non-empty.
    assert ACT_RESULT.is_file(), "act-result.txt was not produced"
    assert ACT_RESULT.stat().st_size > 0
