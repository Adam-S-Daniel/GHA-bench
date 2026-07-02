#!/usr/bin/env python3
"""End-to-end test harness: runs every test case THROUGH the GitHub
Actions workflow using `act` (nektos/act).

For each test case it:
  1. Builds a temp git repo containing the project files plus that
     case's manifest fixture at test-data/manifest (the path the
     workflow's license-report job reads).
  2. Runs `act push --rm` in the temp repo and appends the full output
     to act-result.txt, clearly delimited per case.
  3. Asserts act exited 0, that both jobs report "Job succeeded", and
     that the report contains the EXACT expected per-dependency lines
     and summary for that case's input.

The workflow's `test` job runs the entire pytest suite (unit tests +
workflow structure tests) inside the act container, so every test case
executes through the pipeline. actionlint is asserted here on the host.
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
RESULT_FILE = PROJECT_ROOT / "act-result.txt"
PROJECT_FILES = ["license_checker.py", "tests", "fixtures", ".github", ".actrc"]

# Each case: (name, manifest fixture to feed the pipeline, exact lines that
# MUST appear in the act output for the known-good result of that input).
CASES = [
    (
        "package-json-manifest",
        "fixtures/package.json",
        [
            "express | 4.18.2 | MIT | approved",
            "copyleft-lib | 1.0.0 | GPL-3.0 | denied",
            "jest | 29.0.0 | MIT | approved",
            "mystery-lib | 0.1.0 | UNKNOWN | unknown",
            "Summary: 2 approved, 1 denied, 1 unknown",
        ],
    ),
    (
        "requirements-txt-manifest",
        "fixtures/requirements.txt",
        [
            "requests | 2.31.0 | Apache-2.0 | approved",
            "flask | 3.0.0 | BSD-3-Clause | approved",
            "agpl-tool | 2.0.0 | AGPL-3.0 | denied",
            "Summary: 2 approved, 1 denied, 0 unknown",
        ],
    ),
]

JOBS = ["Unit tests", "License compliance report"]


def run(cmd, cwd, **kwargs):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kwargs)


def build_temp_repo(tmp: Path, manifest_fixture: str) -> None:
    """Copy the project into tmp and install the case's manifest."""
    for name in PROJECT_FILES:
        src = PROJECT_ROOT / name
        if src.is_dir():
            shutil.copytree(src, tmp / name)
        else:
            shutil.copy2(src, tmp / name)
    (tmp / "test-data").mkdir()
    shutil.copy2(PROJECT_ROOT / manifest_fixture, tmp / "test-data" / "manifest")

    for cmd in (
        ["git", "init", "-q", "-b", "main"],
        ["git", "-c", "user.email=ci@example.com", "-c", "user.name=CI", "add", "-A"],
        ["git", "-c", "user.email=ci@example.com", "-c", "user.name=CI",
         "commit", "-q", "-m", "test case"],
    ):
        result = run(cmd, cwd=tmp)
        if result.returncode != 0:
            raise RuntimeError(f"git setup failed: {cmd}\n{result.stderr}")


def main() -> int:
    failures = []
    RESULT_FILE.write_text("", encoding="utf-8")

    # Host-side gate: actionlint must accept the workflow (exit code 0).
    lint = run(["actionlint", ".github/workflows/dependency-license-checker.yml"],
               cwd=PROJECT_ROOT)
    print(f"actionlint exit code: {lint.returncode}")
    if lint.returncode != 0:
        print(lint.stdout + lint.stderr)
        return 1

    for name, manifest_fixture, expected_lines in CASES:
        print(f"\n=== case: {name} ({manifest_fixture}) ===")
        with tempfile.TemporaryDirectory(prefix=f"licchk-{name}-") as tmpdir:
            tmp = Path(tmpdir)
            build_temp_repo(tmp, manifest_fixture)
            result = run(["act", "push", "--rm"], cwd=tmp, timeout=540)
            output = result.stdout + result.stderr

        with RESULT_FILE.open("a", encoding="utf-8") as fh:
            fh.write(f"{'=' * 70}\n=== TEST CASE: {name} (manifest: {manifest_fixture})\n"
                     f"=== act exit code: {result.returncode}\n{'=' * 70}\n")
            fh.write(output + "\n")

        case_failures = []
        if result.returncode != 0:
            case_failures.append(f"act exited {result.returncode}, expected 0")
        for job in JOBS:
            # act reports e.g. "[Dependency License Checker/Unit tests] 🏁  Job succeeded"
            if f"/{job}] " not in output or f"{job}] \U0001F3C1  Job succeeded" not in output:
                case_failures.append(f"job '{job}' did not report success")
        for line in expected_lines:
            if line not in output:
                case_failures.append(f"missing exact expected output: {line!r}")

        if case_failures:
            failures.append((name, case_failures))
            for msg in case_failures:
                print(f"  FAIL: {msg}")
        else:
            print(f"  PASS: exit 0, {len(JOBS)} jobs succeeded, "
                  f"{len(expected_lines)} exact output assertions matched")

    print(f"\nact output saved to {RESULT_FILE}")
    if failures:
        print(f"HARNESS FAILED: {len(failures)} case(s) failed")
        return 1
    print(f"HARNESS PASSED: {len(CASES)}/{len(CASES)} cases green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
