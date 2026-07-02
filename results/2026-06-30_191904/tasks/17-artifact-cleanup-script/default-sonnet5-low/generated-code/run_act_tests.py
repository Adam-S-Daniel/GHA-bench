"""
Test harness that drives the GitHub Actions workflow through `act` and
asserts on exact expected values in its output. Per the task requirements,
no test case is asserted by running the Python script directly -- every
case is verified end-to-end through the pipeline (`act push`).

The workflow's `cleanup` job runs a matrix of two policy test cases against
two fixture files (see fixtures/). This single `act push` invocation
exercises both matrix cells, so all test-case output is captured in one
run and appended to act-result.txt.
"""
import re
import subprocess
import sys

RESULT_FILE = "act-result.txt"

# Each expected test case is a job name (as printed by act) plus the exact
# summary lines that job's script run must produce.
EXPECTED_CASES = [
    {
        "label": "age-and-count-policy",
        "expected_lines": [
            "Retained: 3",
            "Deleted:  1",
            "Space reclaimed: 1000 bytes",
            "Would delete: build-log-3 (1000 bytes, workflow=ci)",
        ],
    },
    {
        "label": "size-budget-policy",
        "expected_lines": [
            "Retained: 2",
            "Deleted:  1",
            "Space reclaimed: 50 bytes",
            "Would delete: art-c (50 bytes, workflow=build)",
        ],
    },
]


def run_act():
    result = subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        capture_output=True, text=True,
    )
    return result.returncode, result.stdout + result.stderr


def main():
    exit_code, output = run_act()

    with open(RESULT_FILE, "a") as f:
        f.write("=" * 70 + "\n")
        f.write("TEST RUN: act push (matrix: age-and-count-policy, size-budget-policy)\n")
        f.write("=" * 70 + "\n")
        f.write(output)
        f.write("\n")

    failures = []

    if exit_code != 0:
        failures.append(f"act exited with code {exit_code}, expected 0")

    job_success_count = len(re.findall(r"Job succeeded", output))
    if job_success_count < 3:  # test job + 2 matrix cells of cleanup job
        failures.append(
            f"expected at least 3 'Job succeeded' messages (1 test job + "
            f"2 matrix cells), found {job_success_count}"
        )

    for case in EXPECTED_CASES:
        for line in case["expected_lines"]:
            if line not in output:
                failures.append(
                    f"[{case['label']}] expected exact output line not found: {line!r}"
                )

    with open(RESULT_FILE, "a") as f:
        if failures:
            f.write("RESULT: FAIL\n")
            for msg in failures:
                f.write(f"  - {msg}\n")
        else:
            f.write("RESULT: PASS -- all test cases produced exact expected values\n")
        f.write("\n")

    if failures:
        print("FAILURES:")
        for msg in failures:
            print(f"  - {msg}")
        return 1

    print("All act-driven test cases passed with exact expected values.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
