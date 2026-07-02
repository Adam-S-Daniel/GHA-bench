"""
End-to-end test of the GitHub Actions workflow, executed for real via `act`
(nektos/act) against a local Docker daemon.

Per the task's explicit instruction, the version-bumping *behavior* (does
1.4.2 + a feat commit really become 1.5.0?) is verified ONLY by running the
real workflow through the real pipeline -- not by calling version_bumper.py
directly from Python. Every one of the six fixture scenarios below is one
matrix job inside the single workflow run, so one `act push` invocation
exercises all six test cases at once (staying well under the 3-run budget).

This test:
  1. Builds a throwaway temp git repo containing the project files + fixtures.
  2. Commits them and runs `act push --rm`, capturing full combined output.
  3. Writes that output to act-result.txt in the CWD (required artifact),
     with the raw log plus a clearly delimited section per test case.
  4. Asserts the act process exited 0.
  5. Asserts every matrix job reports "Job succeeded".
  6. Asserts each test case's RESULT line carries the exact known-good
     version/bumped value for its fixture input -- not just "a version
     appeared somewhere".
"""
import re
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
ACT_RESULT_PATH = REPO_ROOT / "act-result.txt"

# Single source of truth for the known-good outcome of each fixture pair.
# Mirrors the `expected_version` / `expected_bumped` values baked into the
# workflow's matrix (.github/workflows/semantic-version-bumper.yml) -- kept
# here too so the external harness asserts independently, not just trusting
# the workflow's own internal verification step.
EXPECTED_CASES = {
    "feat-bump": {"version": "1.5.0", "bumped": "true"},
    "fix-bump": {"version": "1.4.3", "bumped": "true"},
    "breaking-bump": {"version": "2.0.0", "bumped": "true"},
    "mixed-precedence": {"version": "1.5.0", "bumped": "true"},
    "package-json-bump": {"version": "2.1.0", "bumped": "true"},
    "no-bump": {"version": "1.4.2", "bumped": "false"},
}

RESULT_LINE_RE = re.compile(
    r"RESULT case=(?P<case>\S+) version=(?P<version>\S+) "
    r"bumped=(?P<bumped>\S+) bump_type=(?P<bump_type>\S+)"
)

# Files that make up the project as far as the workflow needs to see it.
PROJECT_ITEMS = ["version_bumper.py", "fixtures", ".github", ".actrc"]


def _build_temp_repo(tmp_path):
    """Set up an isolated git repo containing just what the workflow needs."""
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir()
    for item in PROJECT_ITEMS:
        src = REPO_ROOT / item
        dest = repo_dir / item
        if src.is_dir():
            shutil.copytree(src, dest)
        else:
            shutil.copy2(src, dest)

    run = lambda *args: subprocess.run(
        args, cwd=repo_dir, capture_output=True, text=True, check=True
    )
    run("git", "init", "-q")
    run("git", "config", "user.email", "test@example.com")
    run("git", "config", "user.name", "Test Runner")
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", "test")
    return repo_dir


def _run_act_push(repo_dir):
    """Run `act push --rm` in repo_dir, returning the CompletedProcess."""
    return subprocess.run(
        ["act", "push", "--rm"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        timeout=300,
    )


def _write_act_result_file(full_output, per_case_lines, returncode):
    """Save act's output to act-result.txt, raw output first then a clearly
    delimited section per test case, per the task's required artifact format."""
    parts = [
        "=" * 78,
        "FULL ACT OUTPUT (act push --rm)",
        f"exit code: {returncode}",
        "=" * 78,
        full_output,
        "",
    ]
    for case_name in EXPECTED_CASES:
        parts.append("=" * 78)
        parts.append(f"TEST CASE: {case_name}")
        parts.append("=" * 78)
        lines = per_case_lines.get(case_name, [])
        parts.append("\n".join(lines) if lines else "(no matching output lines found)")
        parts.append("")
    ACT_RESULT_PATH.write_text("\n".join(parts), encoding="utf-8")


def _lines_for_case(full_output, case_name):
    return [line for line in full_output.splitlines() if case_name in line]


@pytest.fixture(scope="session")
def act_run(tmp_path_factory):
    """Run the workflow via act exactly once for the whole test session; all
    per-case assertions below reuse this single run's captured output."""
    tmp_path = tmp_path_factory.mktemp("act-workflow")
    repo_dir = _build_temp_repo(tmp_path)
    result = _run_act_push(repo_dir)
    full_output = (result.stdout or "") + (result.stderr or "")

    per_case_lines = {name: _lines_for_case(full_output, name) for name in EXPECTED_CASES}
    _write_act_result_file(full_output, per_case_lines, result.returncode)

    return {
        "returncode": result.returncode,
        "output": full_output,
        "per_case_lines": per_case_lines,
    }


def test_act_result_file_was_created(act_run):
    assert ACT_RESULT_PATH.is_file()


def test_act_exited_successfully(act_run):
    assert act_run["returncode"] == 0, (
        f"act push exited {act_run['returncode']}; see act-result.txt"
    )


def test_every_matrix_job_succeeded(act_run):
    # fail-fast: false + 6 matrix entries -> exactly 6 successful jobs.
    success_count = act_run["output"].count("Job succeeded")
    assert success_count == len(EXPECTED_CASES), (
        f"expected {len(EXPECTED_CASES)} successful jobs, "
        f"found {success_count} 'Job succeeded' markers"
    )


@pytest.mark.parametrize("case_name", list(EXPECTED_CASES))
def test_case_produces_exact_expected_version(act_run, case_name):
    expected = EXPECTED_CASES[case_name]
    case_lines = act_run["per_case_lines"][case_name]
    result_lines = [RESULT_LINE_RE.search(line) for line in case_lines]
    result_lines = [m for m in result_lines if m]
    assert result_lines, f"no RESULT line found for case {case_name!r} in act output"

    match = result_lines[0]
    assert match.group("case") == case_name
    assert match.group("version") == expected["version"], (
        f"case {case_name}: expected version {expected['version']!r}, "
        f"got {match.group('version')!r}"
    )
    assert match.group("bumped") == expected["bumped"], (
        f"case {case_name}: expected bumped={expected['bumped']!r}, "
        f"got {match.group('bumped')!r}"
    )


@pytest.mark.parametrize("case_name", list(EXPECTED_CASES))
def test_case_workflow_self_verification_passed(act_run, case_name):
    """The workflow's own 'Verify against known-good expected value' step
    prints 'Test case <name> PASSED' -- confirm act actually reached and
    passed that step too, not just that our regex matched a RESULT line."""
    case_lines = act_run["per_case_lines"][case_name]
    assert any(f"Test case {case_name} PASSED" in line for line in case_lines), (
        f"did not find the workflow's own PASSED confirmation for {case_name}"
    )
