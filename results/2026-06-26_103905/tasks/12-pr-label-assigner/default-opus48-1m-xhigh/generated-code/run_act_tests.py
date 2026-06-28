#!/usr/bin/env python3
"""
End-to-end act test harness for the PR Label Assigner workflow.

Per the task requirements, *every* functional test case is executed through the
GitHub Actions pipeline (not by calling the script directly). For each case this
harness:

  1. Builds an isolated temp git repo containing the project files plus that
     case's fixture data (written to ``fixtures/changed-files.txt``).
  2. Runs ``act push --rm`` against the real workflow and captures the output.
  3. Appends the full, clearly-delimited output to ``act-result.txt`` in the
     current working directory.
  4. Asserts act exited 0.
  5. Parses the output and asserts the EXACT expected ``LABELS:`` line.
  6. Asserts every job reported "Job succeeded".

Usage:
    python3 run_act_tests.py                  # run all cases (fresh act-result.txt)
    python3 run_act_tests.py --cases case3    # run a subset (fresh file)
    python3 run_act_tests.py --cases case1 case2 --append   # append to file

Exit code is 0 only if every selected case passes all assertions.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

# Resolve paths relative to this script so it can be run from anywhere.
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT_FILE = os.path.join(PROJECT_DIR, "act-result.txt")
ACT_IMAGE = "act-ubuntu-pwsh:latest"

# Each test case: the fixture file (relative to the project) and the EXACT
# stdout line the workflow must produce for that input. These expected values
# were derived from label-rules.json and verified by the unit tests.
CASES: dict[str, dict[str, str]] = {
    "case1": {
        "fixture": "fixtures/case1_docs.txt",
        "expected": "LABELS: documentation",
    },
    "case2": {
        "fixture": "fixtures/case2_api.txt",
        "expected": "LABELS: api, tests, source",
    },
    "case3": {
        "fixture": "fixtures/case3_mixed.txt",
        "expected": "LABELS: api, tests, documentation, ci, source",
    },
}

# Files/dirs copied into each isolated test repo.
COPY_ITEMS = [
    "pr_label_assigner.py",
    "label-rules.json",
    ".github",
    "fixtures",
    ".actrc",
]


def _run(cmd: list[str], cwd: str, timeout: int = 240) -> subprocess.CompletedProcess:
    """Run a command, capturing combined stdout+stderr as text."""
    return subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def setup_repo(tmp: str, fixture_rel: str) -> None:
    """Populate a temp dir with project files + the case's changed-files list."""
    for item in COPY_ITEMS:
        src = os.path.join(PROJECT_DIR, item)
        dst = os.path.join(tmp, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    # Overwrite the changed-files list the workflow reads with this case's data.
    src_fixture = os.path.join(PROJECT_DIR, fixture_rel)
    shutil.copy2(src_fixture, os.path.join(tmp, "fixtures", "changed-files.txt"))

    # A git repo is required for actions/checkout to operate under act.
    _run(["git", "init", "-q", "-b", "main"], tmp)
    _run(["git", "config", "user.email", "ci@example.com"], tmp)
    _run(["git", "config", "user.name", "CI"], tmp)
    _run(["git", "add", "-A"], tmp)
    _run(["git", "commit", "-q", "-m", "test fixture"], tmp)


def run_case(name: str, append: bool) -> bool:
    """Run a single case through act; return True if all assertions pass."""
    case = CASES[name]
    fixture, expected = case["fixture"], case["expected"]
    print(f"\n=== Running {name} ({fixture}) via act ===")

    tmp = tempfile.mkdtemp(prefix=f"act-{name}-")
    try:
        setup_repo(tmp, fixture)
        # --pull=false: the custom image is local-only (not in a registry).
        result = _run(
            ["act", "push", "--rm", "--pull=false", "-P", f"ubuntu-latest={ACT_IMAGE}"],
            tmp,
        )
        output = result.stdout
        exit_code = result.returncode
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # 2. Persist the raw output with clear delimiters.
    mode = "a" if append else "w"
    with open(RESULT_FILE, mode, encoding="utf-8") as fh:
        fh.write(f"\n{'#' * 78}\n")
        fh.write(f"# TEST CASE: {name}  (fixture: {fixture})\n")
        fh.write(f"# expected: {expected}\n")
        fh.write(f"# act exit code: {exit_code}\n")
        fh.write(f"{'#' * 78}\n")
        fh.write(output)
        fh.write("\n")

    # 3-6. Assertions. Collect every failure so the report is complete.
    failures: list[str] = []
    if exit_code != 0:
        failures.append(f"act exited {exit_code}, expected 0")
    if expected not in output:
        failures.append(f"expected line not found: {expected!r}")
    succeeded = output.count("Job succeeded")
    if succeeded < 2:
        failures.append(f"expected 2 'Job succeeded' (one per job), found {succeeded}")

    if failures:
        print(f"FAIL {name}:")
        for f in failures:
            print(f"  - {f}")
        return False

    print(f"PASS {name}: found {expected!r} and {succeeded} 'Job succeeded'")
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run workflow test cases through act.")
    parser.add_argument(
        "--cases",
        nargs="+",
        choices=list(CASES),
        default=list(CASES),
        help="Which cases to run (default: all).",
    )
    parser.add_argument(
        "--append",
        action="store_true",
        help="Append to act-result.txt instead of truncating it first.",
    )
    args = parser.parse_args(argv)

    if shutil.which("act") is None:
        print("error: 'act' is not installed", file=sys.stderr)
        return 3

    results: dict[str, bool] = {}
    append = args.append
    for name in args.cases:
        ok = run_case(name, append=append)
        results[name] = ok
        # After the first case, always append so we don't clobber prior output.
        append = True

    print("\n==================== SUMMARY ====================")
    for name, ok in results.items():
        print(f"  {name}: {'PASS' if ok else 'FAIL'}")
    print(f"act-result.txt written to: {RESULT_FILE}")

    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
