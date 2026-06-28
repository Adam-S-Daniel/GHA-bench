"""End-to-end tests that drive everything through the GitHub Actions pipeline.

Per the task requirements, the aggregator is NOT exercised directly here -- each
test case runs the real workflow inside a Docker container via `act`. For every
case we:

  1. build a temp git repo containing the project files + that case's fixtures,
  2. run `act push --rm`, capturing the output,
  3. append the output to ``act-result.txt`` in the project directory,
  4. assert act exited 0, both jobs report "Job succeeded", and the workflow
     emitted the EXACT expected totals / flaky tests for that input.

The file also contains pure structure tests (YAML shape, script paths,
actionlint) that do not need a container.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = PROJECT_ROOT / ".github" / "workflows" / "test-results-aggregator.yml"
ACT_RESULT_FILE = PROJECT_ROOT / "act-result.txt"

# Each case: the fixture directory to drop into test-results/, plus the exact
# metrics the workflow must compute for that input. These mirror the values
# verified by the fast unit tests, but here they are asserted against real act
# output. duration is included in the metrics block; the cross-job REPORT line
# carries everything except duration.
CASES = [
    {
        "name": "matrix-with-flaky",
        "expected": {
            "passed": "5", "failed": "1", "errors": "0", "skipped": "2",
            "total": "8", "duration": "7.10", "flaky_count": "1",
            "flaky_tests": "auth.LoginTests.test_flaky",
        },
    },
    {
        "name": "all-pass",
        "expected": {
            "passed": "3", "failed": "0", "errors": "0", "skipped": "0",
            "total": "3", "duration": "0.60", "flaky_count": "0",
            "flaky_tests": "",
        },
    },
    {
        "name": "errors-and-flaky",
        "expected": {
            "passed": "3", "failed": "0", "errors": "1", "skipped": "0",
            "total": "4", "duration": "3.00", "flaky_count": "1",
            "flaky_tests": "math.Arithmetic.test_divide",
        },
    },
]
CASE_NAMES = [c["name"] for c in CASES]


# ===========================================================================
# Helpers
# ===========================================================================
def _have_tools() -> bool:
    """True if both act and docker are usable (so we can run the pipeline)."""
    if not shutil.which("act") or not shutil.which("docker"):
        return False
    try:
        return subprocess.run(
            ["docker", "info"], capture_output=True, timeout=30
        ).returncode == 0
    except Exception:
        return False


def _setup_repo(workdir: Path, case_name: str) -> None:
    """Create a self-contained git repo with the project files + case fixtures."""
    # The workflow only needs the script, the workflow file, and .actrc.
    shutil.copy(PROJECT_ROOT / "aggregate.py", workdir / "aggregate.py")
    shutil.copytree(PROJECT_ROOT / ".github", workdir / ".github")
    shutil.copy(PROJECT_ROOT / ".actrc", workdir / ".actrc")

    # Drop this case's fixtures into the directory the workflow reads.
    results_dir = workdir / "test-results"
    results_dir.mkdir()
    case_dir = PROJECT_ROOT / "fixtures" / "cases" / case_name
    for f in case_dir.iterdir():
        if f.is_file():
            shutil.copy(f, results_dir / f.name)

    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    run = lambda *a: subprocess.run(a, cwd=workdir, env=env, check=True,
                                    capture_output=True, text=True)
    run("git", "init", "-q")
    run("git", "config", "user.email", "ci@example.com")
    run("git", "config", "user.name", "ci")
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", f"fixture: {case_name}")


def _clean_act_line(line: str) -> str:
    """Strip act's '[workflow/job]' prefix and optional '|' marker from a line."""
    line = re.sub(r"^\[[^\]]*\]\s*", "", line)
    line = re.sub(r"^\|\s?", "", line)
    return line.strip()


def _parse_metrics(act_output: str) -> dict:
    """Pull the key=value pairs from the workflow's '=== AGGREGATE METRICS ===' block."""
    metrics: dict[str, str] = {}
    inside = False
    for raw in act_output.splitlines():
        line = _clean_act_line(raw)
        if line == "=== AGGREGATE METRICS ===":
            inside = True
            continue
        if line == "=== END METRICS ===":
            inside = False
            continue
        if inside and "=" in line:
            k, _, v = line.partition("=")
            metrics[k.strip()] = v.strip()
    return metrics


def _find_report_line(act_output: str) -> str | None:
    """Return the cross-job 'REPORT ...' line the report job prints."""
    for raw in act_output.splitlines():
        line = _clean_act_line(raw)
        if line.startswith("REPORT "):
            return line
    return None


def _run_act_for_case(case_name: str) -> dict:
    """Run the workflow under act for one case and return captured results."""
    import tempfile

    with tempfile.TemporaryDirectory(prefix=f"act-{case_name}-") as tmp:
        workdir = Path(tmp)
        _setup_repo(workdir, case_name)
        proc = subprocess.run(
            # --pull=false: the custom image (act-ubuntu-pwsh:latest) is built
            # locally and is not in any registry, so act must not try to pull it.
            ["act", "push", "--rm", "--pull=false"],
            cwd=workdir,
            capture_output=True,
            text=True,
            timeout=600,
        )
    output = proc.stdout + "\n" + proc.stderr
    return {
        "returncode": proc.returncode,
        "output": output,
        "metrics": _parse_metrics(output),
        "report": _find_report_line(output),
        "jobs_succeeded": output.count("Job succeeded"),
    }


# ===========================================================================
# act integration: one real container run per case, results cached for the
# session so act is invoked exactly once per case (3 act runs total).
# ===========================================================================
@pytest.fixture(scope="session")
def act_runs() -> dict:
    if not _have_tools():
        pytest.skip("act/docker not available")

    # Truncate the artifact, then append each case's output with delimiters.
    with open(ACT_RESULT_FILE, "w", encoding="utf-8") as fh:
        fh.write("# act-result.txt -- output of running the workflow via act\n")

    results: dict[str, dict] = {}
    for case in CASES:
        name = case["name"]
        result = _run_act_for_case(name)
        results[name] = result
        with open(ACT_RESULT_FILE, "a", encoding="utf-8") as fh:
            fh.write("\n" + "=" * 72 + "\n")
            fh.write(f"# TEST CASE: {name} (act exit code: {result['returncode']})\n")
            fh.write("=" * 72 + "\n")
            fh.write(result["output"])
            fh.write("\n")
    return results


@pytest.mark.parametrize("case_name", CASE_NAMES)
def test_act_exit_code_zero(act_runs, case_name):
    assert act_runs[case_name]["returncode"] == 0, (
        f"act exited non-zero for {case_name}; see act-result.txt"
    )


@pytest.mark.parametrize("case_name", CASE_NAMES)
def test_act_both_jobs_succeeded(act_runs, case_name):
    # The workflow has two jobs (aggregate + report); both must succeed.
    assert act_runs[case_name]["jobs_succeeded"] >= 2, (
        f"expected 2 'Job succeeded' markers for {case_name}, "
        f"got {act_runs[case_name]['jobs_succeeded']}"
    )


@pytest.mark.parametrize("case", CASES, ids=CASE_NAMES)
def test_act_metrics_exact(act_runs, case):
    """Assert on EXACT computed values parsed from real act output."""
    metrics = act_runs[case["name"]]["metrics"]
    assert metrics == case["expected"], (
        f"metrics mismatch for {case['name']}: got {metrics}"
    )


@pytest.mark.parametrize("case", CASES, ids=CASE_NAMES)
def test_act_report_line_exact(act_runs, case):
    """The dependent job must emit the exact totals it received as job outputs."""
    e = case["expected"]
    expected_report = (
        f"REPORT passed={e['passed']} failed={e['failed']} errors={e['errors']} "
        f"skipped={e['skipped']} total={e['total']} flaky_count={e['flaky_count']} "
        f"flaky_tests={e['flaky_tests']}"
    )
    assert act_runs[case["name"]]["report"] == expected_report


def test_act_result_file_exists(act_runs):
    """The act-result.txt artifact must exist and contain every case."""
    assert ACT_RESULT_FILE.exists()
    text = ACT_RESULT_FILE.read_text()
    for name in CASE_NAMES:
        assert f"TEST CASE: {name}" in text


# ===========================================================================
# Workflow structure tests (no container needed)
# ===========================================================================
def _load_workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text())


def test_workflow_file_exists():
    assert WORKFLOW.exists(), f"missing workflow file: {WORKFLOW}"


def test_workflow_triggers():
    wf = _load_workflow()
    # PyYAML parses the bare `on:` key as the boolean True, so accept either.
    triggers = wf.get("on", wf.get(True))
    assert triggers is not None, "workflow has no triggers"
    for event in ("push", "pull_request", "workflow_dispatch", "schedule"):
        assert event in triggers, f"missing trigger: {event}"
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"


def test_workflow_permissions_least_privilege():
    wf = _load_workflow()
    assert wf["permissions"] == {"contents": "read"}


def test_workflow_jobs_and_dependency():
    wf = _load_workflow()
    jobs = wf["jobs"]
    assert set(jobs) == {"aggregate", "report"}
    # report depends on aggregate.
    assert jobs["report"]["needs"] == "aggregate"
    # aggregate exposes the metrics as job outputs consumed by report.
    assert "passed" in jobs["aggregate"]["outputs"]
    assert "flaky_count" in jobs["aggregate"]["outputs"]


def test_workflow_uses_checkout_and_references_script():
    wf = _load_workflow()
    steps = wf["jobs"]["aggregate"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    assert any(u.startswith("actions/checkout@v4") for u in uses)
    runs = " ".join(s.get("run", "") for s in steps)
    assert "aggregate.py" in runs, "workflow does not invoke aggregate.py"


def test_workflow_referenced_script_paths_exist():
    # Every script the workflow runs must actually exist in the repo.
    assert (PROJECT_ROOT / "aggregate.py").exists()
    # The default results directory the workflow reads must exist too.
    assert (PROJECT_ROOT / "test-results").is_dir()


def test_actionlint_passes():
    if not shutil.which("actionlint"):
        pytest.skip("actionlint not installed")
    proc = subprocess.run(
        ["actionlint", str(WORKFLOW)], capture_output=True, text=True
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
