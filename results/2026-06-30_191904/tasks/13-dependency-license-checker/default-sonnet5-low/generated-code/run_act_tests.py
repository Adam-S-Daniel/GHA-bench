#!/usr/bin/env python3
"""
Test harness that runs the dependency-license-checker workflow through
`act` for each fixture-driven test case, appends the raw output to
act-result.txt, and asserts exact expected values in that output.

Each case copies the project into a fresh temp git repo, swaps in the
case's package.json, then runs `act push --rm`.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
RESULT_FILE = os.path.join(ROOT, "act-result.txt")

PROJECT_FILES = [
    "license_checker.py",
    "fixtures",
    "tests",
    ".github",
]

# Each case overrides fixtures/package.json and states the exact expected
# summary lines that must appear in the act output.
CASES = [
    {
        "name": "all-approved",
        "package_json": {
            "name": "example-app",
            "version": "1.0.0",
            "dependencies": {
                "left-pad": "1.3.0",
                "express": "4.18.2",
            },
            "devDependencies": {
                "jest": "29.0.0",
            },
        },
        "expected_lines": [
            "[APPROVED] left-pad==1.3.0 -> MIT",
            "[APPROVED] express==4.18.2 -> MIT",
            "[APPROVED] jest==29.0.0 -> MIT",
            "Approved: 3",
            "Denied: 0",
            "Unknown: 0",
        ],
    },
    {
        "name": "one-unknown-license",
        "package_json": {
            "name": "example-app",
            "version": "1.0.0",
            "dependencies": {
                "left-pad": "1.3.0",
                "express": "4.18.2",
                "flask": "2.3.2",
            },
            "devDependencies": {
                "jest": "29.0.0",
            },
        },
        "expected_lines": [
            "[UNKNOWN ] flask==2.3.2 -> BSD-3-Clause",
            "Approved: 3",
            "Denied: 0",
            "Unknown: 1",
        ],
    },
]


def setup_case_repo(tmpdir, case):
    for item in PROJECT_FILES:
        src = os.path.join(ROOT, item)
        dst = os.path.join(tmpdir, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    with open(os.path.join(tmpdir, "fixtures", "package.json"), "w", encoding="utf-8") as f:
        json.dump(case["package_json"], f, indent=2)

    actrc_src = os.path.join(ROOT, ".actrc")
    if os.path.isfile(actrc_src):
        shutil.copy2(actrc_src, os.path.join(tmpdir, ".actrc"))

    subprocess.run(["git", "init", "-q"], cwd=tmpdir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
    subprocess.run(["git", "config", "user.name", "Test Runner"], cwd=tmpdir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmpdir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", f"test case: {case['name']}"], cwd=tmpdir, check=True)


def run_case(case):
    with tempfile.TemporaryDirectory(prefix=f"act-{case['name']}-") as tmpdir:
        setup_case_repo(tmpdir, case)
        proc = subprocess.run(
            ["act", "push", "--rm", "--pull=false"],
            cwd=tmpdir,
            capture_output=True,
            text=True,
            timeout=600,
        )
        return proc.returncode, proc.stdout + proc.stderr


def main():
    all_passed = True
    with open(RESULT_FILE, "w", encoding="utf-8") as out:
        for case in CASES:
            out.write(f"===== TEST CASE: {case['name']} =====\n")
            returncode, output = run_case(case)
            out.write(output)
            out.write(f"\n===== EXIT CODE: {returncode} =====\n\n")

            case_ok = True
            if returncode != 0:
                print(f"[FAIL] {case['name']}: act exited {returncode}")
                case_ok = False

            job_success_count = output.count("Job succeeded")
            if job_success_count < 2:
                print(f"[FAIL] {case['name']}: expected 2 'Job succeeded' lines, found {job_success_count}")
                case_ok = False

            for expected in case["expected_lines"]:
                if expected not in output:
                    print(f"[FAIL] {case['name']}: expected line not found: {expected!r}")
                    case_ok = False

            if case_ok:
                print(f"[PASS] {case['name']}")
            else:
                all_passed = False

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
