"""
End-to-end pipeline tests, driven entirely through `act`.

Per the task requirements, functional behavior of the license checker is
NOT unit-tested by importing license_checker.py directly. Instead, each
test case here builds a fresh temp git repository containing a copy of
this project plus that case's fixture manifest, runs the real GitHub
Actions workflow locally with `act push --rm`, and asserts on the exact
text the workflow printed (the `STATUS ...` / `SUMMARY ...` lines emitted
by the "Run dependency license checker" step -- see license_checker.py's
format_text()).

All act output is appended to act-result.txt (in this project's root, the
required artifact), clearly delimited per test case.

Note on TDD/red-green process: because each `act push` invocation costs
30-90 seconds of container startup and there is a hard budget of at most
three invocations for this whole task, the initial "red" phase was
captured once by hand (workflow present, license_checker.py not yet
written) and its output is preserved at the top of act-result.txt. The
two test functions below are the "green" phase: they must pass at the
end, and each corresponds to exactly one of the two remaining act
invocations in the budget.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
ACT_RESULT_PATH = REPO_ROOT / "act-result.txt"

# Files copied into every temp repo before the fixture manifest is overlaid.
PROJECT_FILES = [
    "license_checker.py",
    "policy.json",
    "license_db.json",
    ".github",
    ".actrc",
]


def _make_temp_repo(tmp_path: Path, overlay: dict[str, str]) -> Path:
    """Create a temp git repo with the project files plus fixture overlays.

    `overlay` maps destination-relative-path -> source path (relative to
    REPO_ROOT) whose content should be copied in, e.g.
    {"package.json": "fixtures/case1_package.json"}.
    """
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir()

    for name in PROJECT_FILES:
        src = REPO_ROOT / name
        dst = repo_dir / name
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    for dest_rel, src_rel in overlay.items():
        shutil.copy2(REPO_ROOT / src_rel, repo_dir / dest_rel)

    subprocess.run(["git", "init", "-q"], cwd=repo_dir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_dir, check=True)
    subprocess.run(["git", "config", "user.name", "Test Runner"], cwd=repo_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo_dir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "test case commit"], cwd=repo_dir, check=True)

    return repo_dir


def _run_act_push(repo_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["act", "push", "--rm"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        timeout=300,
    )


def _append_act_result(case_name: str, result: subprocess.CompletedProcess) -> None:
    with ACT_RESULT_PATH.open("a") as f:
        f.write(f"\n{'=' * 80}\nTEST CASE: {case_name}\nEXIT CODE: {result.returncode}\n{'=' * 80}\n")
        f.write(result.stdout)
        f.write(result.stderr)
        f.write("\n")


def test_case_1_mixed_npm_manifest(tmp_path):
    """package.json with 2 approved, 1 denied, 1 unknown dependency."""
    repo_dir = _make_temp_repo(tmp_path, {"package.json": "fixtures/case1_package.json"})
    result = _run_act_push(repo_dir)
    _append_act_result("case1_mixed_npm_manifest", result)

    assert result.returncode == 0, f"act push failed:\n{result.stdout}\n{result.stderr}"
    output = result.stdout

    assert "Job succeeded" in output

    # Exact per-dependency status lines emitted by license_checker.py.
    assert "STATUS left-pad 1.3.0 MIT approved" in output
    assert "STATUS chalk 4.1.2 MIT approved" in output
    assert "STATUS gpl-widget 2.0.0 GPL-3.0 denied" in output
    assert "STATUS mystery-pkg 0.1.0 UNKNOWN unknown" in output

    # Exact aggregate summary.
    assert "SUMMARY approved=2 denied=1 unknown=1 total=4" in output


def test_case_2_pip_requirements_manifest(tmp_path):
    """requirements.txt with 2 approved, 1 denied, 0 unknown dependencies."""
    repo_dir = _make_temp_repo(tmp_path, {"requirements.txt": "fixtures/case2_requirements.txt"})
    # Case 2 has no package.json overlay, but the copied project still has
    # the root package.json from PROJECT_FILES-adjacent copy? No -- package.json
    # is not in PROJECT_FILES, so the repo has only requirements.txt as the
    # manifest, matching resolve_manifest_path()'s package.json-first,
    # requirements.txt-fallback rule.
    result = _run_act_push(repo_dir)
    _append_act_result("case2_pip_requirements_manifest", result)

    assert result.returncode == 0, f"act push failed:\n{result.stdout}\n{result.stderr}"
    output = result.stdout

    assert "Job succeeded" in output

    assert "STATUS requests 2.31.0 Apache-2.0 approved" in output
    assert "STATUS flask 2.3.3 BSD-3-Clause approved" in output
    assert "STATUS copyleft-lib 1.0.0 AGPL-3.0 denied" in output

    assert "SUMMARY approved=2 denied=1 unknown=0 total=3" in output
