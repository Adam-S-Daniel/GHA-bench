#!/usr/bin/env python3
"""End-to-end test harness: every test case runs through GitHub Actions via act.

For each case we build a temp git repo containing the project files plus
that case's fixture config, run `act push --rm`, append the full output to
act-result.txt, and assert:
  * act exited 0
  * exact expected values appear in the output (combo counts, strategy
    options, specific BUILD_OS/BUILD_VERSION legs, error-handling marker)
  * every job in the run reports "Job succeeded" (exact count per case)
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULT_FILE = ROOT / "act-result.txt"

# Files copied into each temp repo. The case fixture then overwrites
# fixtures/config.json, which drives the generate-matrix job.
PROJECT_FILES = [
    ".actrc",
    ".github",
    "fixtures",
    "matrix_generator.py",
    "tests",
]

# Each case: a config fixture and the exact expectations for the act run.
# expected_job_successes = unit-tests + generate-matrix + summary (3)
#                          + one build job per matrix combination.
CASES = [
    {
        "name": "case1-exclude-and-include-extension",
        "config": {
            "os": ["ubuntu-latest", "windows-latest"],
            "version": ["3.11", "3.12"],
            "exclude": [{"os": "windows-latest", "version": "3.11"}],
            "include": [
                {"os": "ubuntu-latest", "version": "3.12", "coverage": True}
            ],
            "fail_fast": False,
            "max_parallel": 2,
            "max_size": 10,
        },
        "expected_strings": [
            "COMBO_COUNT=3",
            "FAIL_FAST=false",
            "MAX_PARALLEL=2",
            "OVERSIZED_REJECTED_OK",
            "BUILD_OS=ubuntu-latest BUILD_VERSION=3.11",
            "BUILD_OS=ubuntu-latest BUILD_VERSION=3.12",
            "BUILD_OS=windows-latest BUILD_VERSION=3.12",
            '"coverage": true',   # include rule extended the matching combo
            "ALL_JOBS_COMPLETE",
            "Ran 18 tests",       # full unit suite executed inside act
        ],
        "absent_strings": [
            # excluded combo must not be built
            "BUILD_OS=windows-latest BUILD_VERSION=3.11",
        ],
        "expected_job_successes": 6,  # 3 fixed jobs + 3 build legs
    },
    {
        "name": "case2-feature-flags",
        "config": {
            "os": ["ubuntu-latest"],
            "version": ["3.12"],
            "features": {"tls": [True, False]},
            "fail_fast": True,
            "max_parallel": 1,
        },
        "expected_strings": [
            "COMBO_COUNT=2",
            "FAIL_FAST=true",
            "MAX_PARALLEL=1",
            "OVERSIZED_REJECTED_OK",
            '"tls": true',        # feature flag expanded into dimensions
            '"tls": false',
            "BUILD_OS=ubuntu-latest BUILD_VERSION=3.12",
            "ALL_JOBS_COMPLETE",
            "Ran 18 tests",
        ],
        "absent_strings": [],
        "expected_job_successes": 5,  # 3 fixed jobs + 2 build legs
    },
    {
        "name": "case3-include-adds-new-combo",
        "config": {
            "os": ["ubuntu-latest"],
            "version": ["3.11", "3.12"],
            "include": [{"os": "macos-14", "version": "3.13"}],
            "fail_fast": False,
            "max_parallel": 3,
            "max_size": 5,
        },
        "expected_strings": [
            "COMBO_COUNT=3",
            "FAIL_FAST=false",
            "MAX_PARALLEL=3",
            "OVERSIZED_REJECTED_OK",
            "BUILD_OS=ubuntu-latest BUILD_VERSION=3.11",
            "BUILD_OS=ubuntu-latest BUILD_VERSION=3.12",
            "BUILD_OS=macos-14 BUILD_VERSION=3.13",  # brand-new combo
            "ALL_JOBS_COMPLETE",
            "Ran 18 tests",
        ],
        "absent_strings": [],
        "expected_job_successes": 6,  # 3 fixed jobs + 3 build legs
    },
]


def build_temp_repo(case, tmpdir):
    """Copy project files + the case fixture into a fresh git repo."""
    repo = Path(tmpdir) / case["name"]
    repo.mkdir()
    for name in PROJECT_FILES:
        src = ROOT / name
        if src.is_dir():
            shutil.copytree(src, repo / name)
        else:
            shutil.copy2(src, repo / name)
    # Overwrite the default config with this case's fixture data.
    (repo / "fixtures" / "config.json").write_text(
        json.dumps(case["config"], indent=2), encoding="utf-8"
    )
    run = lambda *cmd: subprocess.run(
        cmd, cwd=repo, check=True, capture_output=True, text=True
    )
    run("git", "init", "-q")
    run("git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A")
    run(
        "git", "-c", "user.email=t@t", "-c", "user.name=t",
        "commit", "-qm", f"fixture {case['name']}",
    )
    return repo


def run_case(case, tmpdir):
    repo = build_temp_repo(case, tmpdir)
    proc = subprocess.run(
        # --pull=false: the runner image exists only locally (see .actrc);
        # forcing a registry pull fails with an auth error.
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=600,
    )
    output = proc.stdout + "\n--- stderr ---\n" + proc.stderr

    with RESULT_FILE.open("a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 70}\n=== TEST CASE: {case['name']} ===\n{'=' * 70}\n")
        fh.write(output)
        fh.write(f"\n=== EXIT CODE: {proc.returncode} ===\n")

    failures = []
    if proc.returncode != 0:
        failures.append(f"act exited with {proc.returncode}, expected 0")
    for needle in case["expected_strings"]:
        if needle not in output:
            failures.append(f"missing expected output: {needle!r}")
    for needle in case["absent_strings"]:
        if needle in output:
            failures.append(f"unexpected output present: {needle!r}")
    successes = output.count("Job succeeded")
    if successes != case["expected_job_successes"]:
        failures.append(
            f"expected {case['expected_job_successes']} 'Job succeeded' "
            f"lines, found {successes}"
        )
    return failures


def main():
    RESULT_FILE.write_text("act end-to-end test results\n", encoding="utf-8")
    all_ok = True
    with tempfile.TemporaryDirectory(prefix="act-matrix-") as tmpdir:
        for case in CASES:
            print(f"[RUN ] {case['name']}", flush=True)
            failures = run_case(case, tmpdir)
            if failures:
                all_ok = False
                print(f"[FAIL] {case['name']}")
                for f in failures:
                    print(f"       - {f}")
            else:
                print(f"[PASS] {case['name']}")

    with RESULT_FILE.open("a", encoding="utf-8") as fh:
        fh.write(
            f"\n=== OVERALL: {'ALL CASES PASSED' if all_ok else 'FAILURES'} ===\n"
        )
    print(f"\nResults appended to {RESULT_FILE}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
