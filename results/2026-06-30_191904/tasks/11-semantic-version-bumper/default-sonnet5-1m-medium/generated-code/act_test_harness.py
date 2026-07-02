#!/usr/bin/env python3
"""
Integration test harness: runs the semantic-version-bumper workflow through
`act` (never by invoking version_bumper.py directly) and asserts on the
actual pipeline output.

For each of the three fixture-driven scenarios (patch/minor/major bump) the
workflow's matrix produces one job. A single `act push --rm` invocation
executes the whole matrix in one shot, so all three test cases are covered
without exceeding the "at most 3 act push runs" budget.

Steps:
  1. Set up a temporary git repo containing the project files + fixtures.
  2. Run `act push --rm`, capturing combined stdout/stderr.
  3. Append the captured output to act-result.txt in the current directory.
  4. Assert act exited 0.
  5. Assert each matrix job reports "Job succeeded".
  6. Assert the exact expected version string appears for each scenario.
"""
import os
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
RESULT_FILE = os.path.join(REPO_ROOT, "act-result.txt")

PROJECT_FILES = ["version_bumper.py", "fixtures", ".github", ".actrc"]

# (job name suffix as it appears in act's log lines, expected new version)
EXPECTED_CASES = [
    ("patch", "1.0.1"),
    ("minor", "1.1.0"),
    ("major", "2.0.0"),
]


def _make_temp_repo():
    tmp_dir = tempfile.mkdtemp(prefix="version-bumper-act-")
    for name in PROJECT_FILES:
        src = os.path.join(REPO_ROOT, name)
        dst = os.path.join(tmp_dir, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    subprocess.run(["git", "init", "-q"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.name", "Test Harness"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "feat: seed project for act test"], cwd=tmp_dir, check=True)
    return tmp_dir


def run_act_and_capture():
    tmp_dir = _make_temp_repo()
    try:
        result = subprocess.run(
            ["act", "push", "--rm", "--pull=false"],
            cwd=tmp_dir,
            capture_output=True,
            text=True,
            timeout=600,
        )
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
    return result


def main():
    result = run_act_and_capture()
    output = result.stdout + "\n" + result.stderr

    with open(RESULT_FILE, "a") as fh:
        fh.write("=" * 80 + "\n")
        fh.write("TEST CASE: semantic-version-bumper full matrix (patch/minor/major)\n")
        fh.write(f"exit_code={result.returncode}\n")
        fh.write("-" * 80 + "\n")
        fh.write(output)
        fh.write("\n")

    failures = []

    if result.returncode != 0:
        failures.append(f"act exited with code {result.returncode}, expected 0")

    succeeded_jobs = output.count("Job succeeded")
    if succeeded_jobs < 3:
        failures.append(f"expected 3 'Job succeeded' lines (one per matrix case), found {succeeded_jobs}")

    for case_name, expected_version in EXPECTED_CASES:
        if expected_version not in output:
            failures.append(
                f"case '{case_name}': expected exact version '{expected_version}' not found in act output"
            )

    if failures:
        print("ACT HARNESS FAILED:")
        for f in failures:
            print(f" - {f}")
        return 1

    print("ACT HARNESS PASSED: all 3 matrix cases produced exact expected versions and succeeded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
