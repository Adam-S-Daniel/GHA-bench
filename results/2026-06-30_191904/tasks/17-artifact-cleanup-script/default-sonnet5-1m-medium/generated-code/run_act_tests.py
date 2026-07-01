"""
Test harness that drives the artifact-cleanup GitHub Actions workflow
through `act` and asserts exact expected output.

Two test cases exercise the workflow's two behaviors:
  1. `push` event -> dry-run planning (the workflow's default when
     `github.event.inputs.dry_run` is unset).
  2. `workflow_dispatch` event with `inputs.dry_run=false` -> live run,
     which invokes the mock deleter for each artifact.

Both cases use the same fixture (fixtures/sample_artifacts.json) and the
same policy (MAX_AGE_DAYS=20, KEEP_LATEST_N_PER_WORKFLOW=1 from the
workflow's `env:` block), so both must produce the identical, hand-computed
SUMMARY line: artifacts_deleted=2 artifacts_retained=3
space_reclaimed_bytes=1500 (ci-build-1 and test-report-1 are the only
artifacts older than 20 days that are not the newest in their workflow).

Each test case is run in an isolated temporary git repository containing a
copy of this project, via `act push --rm` / `act workflow_dispatch --rm`.
Output is appended to act-result.txt, clearly delimited per case, and every
assertion below is checked against that captured output before the script
reports success.
"""
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.resolve()
RESULT_FILE = PROJECT_ROOT / "act-result.txt"

EXPECTED_SUMMARY = "SUMMARY: artifacts_deleted=2 artifacts_retained=3 space_reclaimed_bytes=1500"
EXPECTED_JOBS = ["Run unit tests", "Generate artifact cleanup plan"]

TEST_CASES = [
    {
        "name": "case1_push_dry_run",
        "act_args": ["act", "push", "--rm", "--pull=false"],
        "expect_in_output": ["DRY RUN", EXPECTED_SUMMARY],
    },
    {
        "name": "case2_workflow_dispatch_live_run",
        "act_args": [
            "act", "workflow_dispatch", "--rm", "--pull=false",
            "-e", "fixtures/dispatch_live_run_event.json",
        ],
        "expect_in_output": [
            "LIVE RUN",
            "deleted: ci-build-1",
            "deleted: test-report-1",
            EXPECTED_SUMMARY,
        ],
    },
]

# Files that must exist in the temp repo for the workflow to run correctly.
PROJECT_FILES = [
    "artifact_cleanup.py",
    "cli.py",
    "conftest.py",
    "pyproject.toml",
    "tests",
    "fixtures",
    ".github",
]


def _make_temp_repo(tmp_dir: Path) -> Path:
    """Copy project files into an isolated temp directory and git-init it,
    so each act run starts from a clean, self-contained repo."""
    repo_dir = tmp_dir / "repo"
    repo_dir.mkdir()
    for name in PROJECT_FILES:
        src = PROJECT_ROOT / name
        dst = repo_dir / name
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    subprocess.run(["git", "init", "-q"], cwd=repo_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo_dir, check=True)
    subprocess.run(
        ["git", "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "test"],
        cwd=repo_dir,
        check=True,
    )
    shutil.copy2(PROJECT_ROOT / ".actrc", repo_dir / ".actrc")
    return repo_dir


def run_case(case: dict, tmp_root: Path) -> tuple:
    """Run one test case in its own temp git repo and return (output, returncode)."""
    repo_dir = _make_temp_repo(tmp_root / case["name"])
    proc = subprocess.run(
        case["act_args"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        timeout=300,
    )
    return proc.stdout + proc.stderr, proc.returncode


def assert_case(case: dict, output: str, returncode: int) -> None:
    assert returncode == 0, f"{case['name']}: act exited {returncode}, expected 0"
    for job in EXPECTED_JOBS:
        marker = f"[Artifact Cleanup Script/{job}] \U0001f3c1  Job succeeded"
        assert marker in output, f"{case['name']}: missing '{marker}'"
    for expected in case["expect_in_output"]:
        assert expected in output, f"{case['name']}: missing expected output {expected!r}"


def main() -> int:
    import tempfile

    sections = []
    all_passed = True

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp)
        for case in TEST_CASES:
            print(f"Running test case: {case['name']}")
            output, returncode = run_case(case, tmp_root)
            try:
                assert_case(case, output, returncode)
                status = "PASS"
            except AssertionError as exc:
                status = f"FAIL: {exc}"
                all_passed = False
            print(f"  {status}")

            sections.append(
                "\n".join(
                    [
                        f"===== TEST CASE: {case['name']} =====",
                        f"command: {' '.join(case['act_args'])}",
                        f"exit_code: {returncode}",
                        f"assertion: {status}",
                        "----- act output -----",
                        output,
                        f"===== END TEST CASE: {case['name']} =====\n",
                    ]
                )
            )

    RESULT_FILE.write_text("\n".join(sections))
    print(f"\nWrote {RESULT_FILE}")
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
