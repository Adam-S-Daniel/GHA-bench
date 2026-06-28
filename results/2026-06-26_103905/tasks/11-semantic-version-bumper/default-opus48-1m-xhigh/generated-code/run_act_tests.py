#!/usr/bin/env python3
"""Integration test harness: run the workflow through `act` for each case.

Per the task requirements, every integration test executes the *real*
GitHub Actions workflow via ``act`` (nektos/act) rather than calling the
script directly.  For each test case this harness:

  1. Builds an isolated temp git repo containing the project files plus that
     case's fixture commit log.
  2. Runs ``act push --rm`` inside it and captures the output.
  3. Appends the captured output to ``act-result.txt`` (clearly delimited).
  4. Asserts act exited 0, that the output contains the EXACT expected
     version / bump type, and that every job reports "Job succeeded".

Run with:  python3 run_act_tests.py
Exits 0 only if every assertion for every case holds.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Project root = directory containing this script.
ROOT = Path(__file__).resolve().parent
WORKFLOW_REL = Path(".github/workflows/semantic-version-bumper.yml")
ACT_RESULT = Path.cwd() / "act-result.txt"

# Files copied verbatim into every temp repo.
PROJECT_FILES = ["semver_bumper.py", "CHANGELOG.md"]

# Each case starts from version 1.1.0 so the three bump types produce three
# distinct, known-good results.  These are EXACT expected values.
CASES = [
    {
        "name": "patch-from-fix",
        "fixture": "tests/fixtures/fix_commits.log",
        "start_version": "1.1.0",
        "expected_version": "1.1.1",
        "expected_bump": "patch",
    },
    {
        "name": "minor-from-feat",
        "fixture": "tests/fixtures/feat_commits.log",
        "start_version": "1.1.0",
        "expected_version": "1.2.0",
        "expected_bump": "minor",
    },
    {
        "name": "major-from-breaking",
        "fixture": "tests/fixtures/breaking_commits.log",
        "start_version": "1.1.0",
        "expected_version": "2.0.0",
        "expected_bump": "major",
    },
]

GIT_ID = ["-c", "user.email=ci@example.com", "-c", "user.name=CI Harness"]


def build_repo(case: dict, dest: Path) -> None:
    """Materialize an isolated git repo for one test case under ``dest``."""
    (dest / WORKFLOW_REL.parent).mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / WORKFLOW_REL, dest / WORKFLOW_REL)

    for name in PROJECT_FILES:
        shutil.copy(ROOT / name, dest / name)

    # Copy .actrc so act uses the python-capable container image.
    actrc = ROOT / ".actrc"
    if actrc.exists():
        shutil.copy(actrc, dest / ".actrc")

    # Per-case inputs: the starting version and that case's commit log.
    (dest / "VERSION").write_text(case["start_version"] + "\n")
    (dest / "commits.log").write_text((ROOT / case["fixture"]).read_text())

    # A committed repo is required for `act push`.
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=dest, check=True)
    subprocess.run(["git", *GIT_ID, "add", "-A"], cwd=dest, check=True)
    subprocess.run(
        ["git", *GIT_ID, "commit", "-q", "-m", "chore: set up test case"],
        cwd=dest, check=True,
    )


def run_act(dest: Path) -> subprocess.CompletedProcess:
    """Run the workflow through act for the repo at ``dest``."""
    return subprocess.run(
        # --pull=false: the container image is pre-built locally.
        ["act", "push", "--rm", "--pull=false"],
        cwd=dest,
        capture_output=True,
        text=True,
        timeout=600,
    )


def check_case(case: dict, proc: subprocess.CompletedProcess) -> list[str]:
    """Return a list of assertion-failure messages (empty == all passed)."""
    output = proc.stdout + "\n" + proc.stderr
    failures: list[str] = []

    if proc.returncode != 0:
        failures.append(f"act exited {proc.returncode}, expected 0")

    expected_version = f"NEW_VERSION={case['expected_version']}"
    if expected_version not in output:
        failures.append(f"expected output to contain '{expected_version}'")

    expected_bump = f"BUMP_TYPE={case['expected_bump']}"
    if expected_bump not in output:
        failures.append(f"expected output to contain '{expected_bump}'")

    # Both the `bump` and `verify` jobs must succeed.
    succeeded = output.count("Job succeeded")
    if succeeded < 2:
        failures.append(
            f"expected >=2 'Job succeeded' (bump + verify), saw {succeeded}"
        )

    return failures


def main() -> int:
    # Truncate the result artifact once, then append per case.
    ACT_RESULT.write_text(
        "act integration results for semantic-version-bumper\n"
        "===================================================\n"
    )

    all_passed = True
    for case in CASES:
        tmp = Path(tempfile.mkdtemp(prefix=f"svb-{case['name']}-"))
        header = (
            f"\n\n########################################\n"
            f"# CASE: {case['name']}\n"
            f"#   start={case['start_version']} fixture={case['fixture']}\n"
            f"#   expected NEW_VERSION={case['expected_version']} "
            f"BUMP_TYPE={case['expected_bump']}\n"
            f"########################################\n"
        )
        try:
            build_repo(case, tmp)
            proc = run_act(tmp)
            body = proc.stdout + "\n--- stderr ---\n" + proc.stderr
            failures = check_case(case, proc)
        except Exception as exc:  # pragma: no cover - defensive
            body = f"HARNESS ERROR: {exc!r}"
            failures = [f"harness raised: {exc!r}"]
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

        with ACT_RESULT.open("a") as fh:
            fh.write(header)
            fh.write(body)
            fh.write(
                f"\n--- assertions for {case['name']}: "
                f"{'PASS' if not failures else 'FAIL'} ---\n"
            )
            for msg in failures:
                fh.write(f"    - {msg}\n")

        status = "PASS" if not failures else "FAIL"
        print(f"[{status}] {case['name']}")
        for msg in failures:
            print(f"        {msg}")
        all_passed = all_passed and not failures

    print(f"\nFull act output saved to: {ACT_RESULT}")
    if all_passed:
        print("ALL ACT INTEGRATION TESTS PASSED")
        return 0
    print("SOME ACT INTEGRATION TESTS FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
