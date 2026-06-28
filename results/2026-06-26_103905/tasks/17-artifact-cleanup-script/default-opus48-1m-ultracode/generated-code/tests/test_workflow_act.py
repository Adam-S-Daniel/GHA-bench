"""
End-to-end test: run the workflow in Docker via ``act`` and assert on exact,
known-good output for every fixture case.

The workflow uses a matrix (one job per fixture case), so a *single* ``act push``
exercises all cases at once. This is deliberate: ``act`` runs take ~30-90s of
container time, and the benchmark caps total ``act push`` invocations. The matrix
gives us per-case isolation (separate jobs, separate "Job succeeded" lines, each
line prefixed with its case name) while spending only one run.

The full ``act`` log plus a parsed, per-case breakdown is written to
``act-result.txt`` in the project root — a required artifact.

This test is gated behind ``RUN_ACT=1`` so the fast unit/structure suite does not
spin up Docker on every invocation. Run it explicitly with::

    RUN_ACT=1 python3 -m pytest tests/test_workflow_act.py -v -s
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ACT_RESULT = PROJECT_ROOT / "act-result.txt"

# Files the temp git repo needs to run the workflow.
PROJECT_FILES = ["artifact_cleanup.py", ".actrc"]
PROJECT_DIRS = ["fixtures", ".github"]

# Known-good values for each fixture case (hand-computed; see fixtures/*.json).
EXPECTED = {
    "keep_n": {"DELETED_COUNT": 1, "RETAINED_COUNT": 4, "SPACE_RECLAIMED": 100},
    "age": {"DELETED_COUNT": 2, "RETAINED_COUNT": 3, "SPACE_RECLAIMED": 3000},
    "size": {"DELETED_COUNT": 3, "RETAINED_COUNT": 1, "SPACE_RECLAIMED": 1800},
    "combined": {"DELETED_COUNT": 4, "RETAINED_COUNT": 3, "SPACE_RECLAIMED": 1800},
    "empty": {"DELETED_COUNT": 0, "RETAINED_COUNT": 0, "SPACE_RECLAIMED": 0},
}

# 5 matrix jobs + the dependent summary job.
EXPECTED_JOB_SUCCESS = 6

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_ACT") != "1",
    reason="set RUN_ACT=1 to run the Docker/act integration test",
)


def _build_temp_repo(tmp_path: Path) -> Path:
    """Create an isolated git repo containing the project + fixtures."""
    repo = tmp_path / "repo"
    repo.mkdir()
    for name in PROJECT_FILES:
        src = PROJECT_ROOT / name
        if src.exists():
            shutil.copy2(src, repo / name)
    for name in PROJECT_DIRS:
        shutil.copytree(PROJECT_ROOT / name, repo / name)

    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True, env=env)
    subprocess.run(["git", "config", "user.email", "test@test"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=repo, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "commit", "-q", "-m", "act test fixture"], cwd=repo, check=True, env=env
    )
    return repo


def _case_values(output: str, case: str) -> dict:
    """Extract KEY=value metrics for one matrix case from the act log.

    ``act`` prefixes every output line with the job tag, e.g.
    ``[Artifact Cleanup/cleanup (combined)-4]   DELETED_COUNT=4``. Filtering by
    ``cleanup (<case>)`` is robust even when parallel matrix jobs interleave.
    """
    tag = f"cleanup ({case})"
    values: dict[str, int] = {}
    for line in output.splitlines():
        if tag not in line:
            continue
        for key in ("DELETED_COUNT", "RETAINED_COUNT", "SPACE_RECLAIMED", "DRY_RUN"):
            marker = f"{key}="
            if marker in line:
                raw = line.split(marker, 1)[1].strip()
                values[key] = raw if key == "DRY_RUN" else int(raw)
    return values


def _write_result_file(cmd: str, returncode: int, output: str, parsed: dict) -> None:
    """Persist the full act log plus a per-case parsed breakdown."""
    sep = "=" * 78
    parts = [
        sep,
        "ARTIFACT CLEANUP — act push integration result",
        f"Command : {cmd}",
        f"Exit    : {returncode}",
        sep,
        "",
        "RAW ACT OUTPUT",
        "-" * 78,
        output,
        "",
        sep,
        "PER-CASE PARSED RESULTS (clearly delimited)",
        sep,
    ]
    for case, expected in EXPECTED.items():
        got = parsed.get(case, {})
        ok = all(got.get(k) == v for k, v in expected.items())
        parts += [
            "",
            f"----- CASE: {case} -----",
            f"  expected: {expected}",
            f"  actual  : {{'DELETED_COUNT': {got.get('DELETED_COUNT')}, "
            f"'RETAINED_COUNT': {got.get('RETAINED_COUNT')}, "
            f"'SPACE_RECLAIMED': {got.get('SPACE_RECLAIMED')}, "
            f"'DRY_RUN': {got.get('DRY_RUN')!r}}}",
            f"  verdict : {'PASS' if ok else 'FAIL'}",
        ]
    parts.append("")
    ACT_RESULT.write_text("\n".join(parts))


def test_workflow_runs_through_act(tmp_path):
    if shutil.which("act") is None:
        pytest.skip("act is not installed")

    repo = _build_temp_repo(tmp_path)

    # --pull=false: the act image (act-ubuntu-pwsh:latest) is built locally and is
    # not in any registry, so we must not attempt a network pull. The platform
    # mapping comes from the copied .actrc.
    cmd = ["act", "push", "--rm", "--pull=false"]
    proc = subprocess.run(
        cmd,
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=600,
    )
    output = proc.stdout + "\n" + proc.stderr

    parsed = {case: _case_values(output, case) for case in EXPECTED}
    _write_result_file(" ".join(cmd), proc.returncode, output, parsed)

    # 1. act must succeed overall.
    assert proc.returncode == 0, (
        f"act exited {proc.returncode}; see {ACT_RESULT}"
    )

    # 2. Every job must report success (5 matrix cases + summary).
    success_count = output.count("Job succeeded")
    assert success_count >= EXPECTED_JOB_SUCCESS, (
        f"expected >= {EXPECTED_JOB_SUCCESS} 'Job succeeded', got {success_count}"
    )

    # 3. Each case must produce its exact, known-good metrics.
    for case, expected in EXPECTED.items():
        got = parsed[case]
        for key, value in expected.items():
            assert got.get(key) == value, (
                f"case {case}: expected {key}={value}, got {got.get(key)}"
            )
        # Workflow runs in dry-run mode for every case.
        assert got.get("DRY_RUN") == "true", f"case {case}: DRY_RUN != true"

    # 4. The required artifact must exist.
    assert ACT_RESULT.exists()
