"""End-to-end tests that run the workflow through `act` (nektos/act) in Docker.

Every functional test case is exercised *through the GitHub Actions pipeline*,
not by calling the script directly. For each case we:

  1. build a throwaway git repo containing the project files + that case's
     fixture data (copied over the workflow's default fixture paths),
  2. run ``act push`` in a container,
  3. append the full output to ``act-result.txt`` (clearly delimited),
  4. assert act exited 0, that the plan's RESULT line matches the known-good
     values exactly, and that every job reports "Job succeeded".

The container image is pinned and ``--pull=false`` is passed so the run is fully
offline and deterministic. There are three cases, i.e. three ``act push`` runs.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
ACT_RESULT = ROOT / "act-result.txt"
IMAGE = "act-ubuntu-pwsh:latest"

# Each case: the per-case fixture dir under fixtures/cases/ and the EXACT,
# pre-computed RESULT marker the dry-run plan must emit (frozen reference time
# 2026-06-28T12:00:00Z is set in the workflow env).
CASES = [
    (
        "01-max-age",
        "RESULT total=4 retained=2 deleted=2 reclaimed=3000 retained_bytes=7000 total_bytes=10000",
    ),
    (
        "02-keep-latest-n",
        "RESULT total=5 retained=2 deleted=3 reclaimed=1300 retained_bytes=2300 total_bytes=3600",
    ),
    (
        "03-combined",
        "RESULT total=5 retained=1 deleted=4 reclaimed=12000 retained_bytes=3000 total_bytes=15000",
    ),
]

# Skip (rather than hard-fail) only if the tooling genuinely isn't present.
pytestmark = pytest.mark.skipif(
    shutil.which("act") is None or shutil.which("docker") is None,
    reason="act and/or docker not available",
)


@pytest.fixture(scope="module", autouse=True)
def _fresh_act_result():
    """Truncate act-result.txt once so the module run starts clean."""
    ACT_RESULT.write_text("")
    yield


def _build_case_repo(repo: Path, case_name: str) -> None:
    """Populate a temp git repo with project files + this case's fixtures."""
    # Copy the pieces the workflow needs.
    shutil.copy(ROOT / "artifact_cleanup.py", repo / "artifact_cleanup.py")
    shutil.copytree(ROOT / ".github", repo / ".github")
    shutil.copytree(ROOT / "fixtures", repo / "fixtures")
    if (ROOT / ".actrc").is_file():
        shutil.copy(ROOT / ".actrc", repo / ".actrc")

    # Overwrite the workflow's default fixture paths with this case's data.
    case_dir = ROOT / "fixtures" / "cases" / case_name
    shutil.copy(case_dir / "artifacts.json", repo / "fixtures" / "artifacts.json")
    shutil.copy(case_dir / "policy.json", repo / "fixtures" / "policy.json")

    # A committed repo is required: act's checkout sees only committed files.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    run = lambda *a: subprocess.run(a, cwd=repo, check=True, capture_output=True, env=env)
    run("git", "init", "-q")
    run("git", "config", "user.email", "ci@example.com")
    run("git", "config", "user.name", "ci")
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", f"case {case_name}")


def _run_act(repo: Path) -> subprocess.CompletedProcess:
    """Run `act push` for the repo, image pinned and network disabled."""
    return subprocess.run(
        [
            "act", "push",
            "--rm",
            "--pull=false",
            "-P", f"ubuntu-latest={IMAGE}",
        ],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=600,
    )


def _append_result(case_name: str, proc: subprocess.CompletedProcess) -> None:
    """Append this case's act output to act-result.txt, clearly delimited."""
    with ACT_RESULT.open("a", encoding="utf-8") as fh:
        fh.write("=" * 78 + "\n")
        fh.write(f"CASE: {case_name}\n")
        fh.write(f"act exit code: {proc.returncode}\n")
        fh.write("-" * 78 + "\n")
        fh.write(proc.stdout)
        if proc.stderr:
            fh.write("\n--- stderr ---\n")
            fh.write(proc.stderr)
        fh.write("\n\n")


@pytest.mark.parametrize("case_name,expected_result", CASES, ids=[c[0] for c in CASES])
def test_workflow_runs_through_act(tmp_path, case_name, expected_result):
    repo = tmp_path / "repo"
    repo.mkdir()
    _build_case_repo(repo, case_name)

    proc = _run_act(repo)
    _append_result(case_name, proc)
    combined = proc.stdout + "\n" + proc.stderr

    # 1) act must succeed.
    assert proc.returncode == 0, (
        f"act exited {proc.returncode} for {case_name}. Tail:\n"
        + "\n".join(combined.splitlines()[-40:])
    )

    # 2) The plan's RESULT line must match the known-good values exactly.
    assert expected_result in combined, (
        f"expected RESULT line not found for {case_name}.\nWanted: {expected_result}\n"
        "Got tail:\n" + "\n".join(combined.splitlines()[-40:])
    )

    # 3) Dry-run is the default in CI.
    assert "[DRY RUN]" in combined

    # 4) Every job must report success (validate + cleanup), and none fail.
    assert "Job failed" not in combined, f"a job failed for {case_name}"
    assert combined.count("Job succeeded") >= 2, (
        f"expected both jobs to succeed for {case_name}; "
        f"found {combined.count('Job succeeded')} 'Job succeeded' markers"
    )


def test_act_result_file_exists_after_cases():
    """The required act-result.txt artifact must exist and hold every case."""
    assert ACT_RESULT.is_file()
    content = ACT_RESULT.read_text()
    for case_name, _ in CASES:
        assert f"CASE: {case_name}" in content
