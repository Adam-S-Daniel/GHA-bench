"""End-to-end test harness: every test case runs through the GitHub Actions
workflow via `act` (nektos/act), never against the script directly.

For each case it:
  1. builds a temp git repo containing the project files plus that case's
     fixture data (artifacts inventory, retention policy, pinned "now"),
  2. runs `act push --rm` in it,
  3. appends the full act output to act-result.txt (clearly delimited),
  4. asserts act exited 0, that BOTH jobs report "Job succeeded", and that
     the output contains the exact known-good values for that input.

Workflow structure tests (YAML shape + actionlint) run first, before any
act time is spent.

Usage: python3 run_act_tests.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT_FILE = os.path.join(PROJECT_DIR, "act-result.txt")
# Files/dirs the workflow needs inside each temp repo.
PROJECT_FILES = ["artifact_cleanup.py", "tests", ".github"]
ACT_CMD = [
    "act", "push", "--rm",
    "-P", "ubuntu-latest=act-ubuntu-pwsh:latest",
    "--pull=false",
    "--action-offline-mode",
]
JOB_NAMES = ["Unit tests", "Cleanup plan"]

# ---------------------------------------------------------------------------
# Test cases. `expected` substrings are EXACT known-good values, derived by
# hand from each case's inputs (see comments), not from running the script.
# ---------------------------------------------------------------------------
CASES = [
    {
        # All three policies fire at once (reference time 2026-07-01):
        #  - old-build-logs (2026-05-01) is 61 days old   -> max-age (>30)
        #  - run 100 has 3 artifacts, keep_latest_n=2     -> rank 3 deleted
        #  - survivors total 14 MB against a 10 MB cap    -> evict oldest (4 MB)
        # Deleted: 2 MB + 3 MB + 4 MB = 9 MB reclaimed; 3 retained (10 MB).
        "name": "combined-policies",
        "now": "2026-07-01T00:00:00Z",
        "artifacts": [
            {"name": "old-build-logs", "size_bytes": 2097152,
             "created_at": "2026-05-01T00:00:00Z", "workflow_run_id": 99},
            {"name": "run1-artifact-a", "size_bytes": 3145728,
             "created_at": "2026-06-10T00:00:00Z", "workflow_run_id": 100},
            {"name": "run1-artifact-b", "size_bytes": 4194304,
             "created_at": "2026-06-15T00:00:00Z", "workflow_run_id": 100},
            {"name": "run1-artifact-c", "size_bytes": 1048576,
             "created_at": "2026-06-20T00:00:00Z", "workflow_run_id": 100},
            {"name": "run2-artifact-a", "size_bytes": 5242880,
             "created_at": "2026-06-25T00:00:00Z", "workflow_run_id": 200},
            {"name": "run2-artifact-b", "size_bytes": 4194304,
             "created_at": "2026-06-28T00:00:00Z", "workflow_run_id": 200},
        ],
        "policy": {"max_age_days": 30, "keep_latest_n": 2,
                   "max_total_size_bytes": 10485760},
        "expected": [
            "DELETE old-build-logs (2.00 MB) - max-age: 61 days old exceeds limit of 30 days",
            "DELETE run1-artifact-a (3.00 MB) - keep-latest: rank 3 of 3 in workflow run 100 exceeds keep-latest limit of 2",
            "DELETE run1-artifact-b (4.00 MB) - max-total-size: retained total 14.00 MB exceeds limit of 10.00 MB",
            "KEEP   run1-artifact-c (1.00 MB)",
            "KEEP   run2-artifact-a (5.00 MB)",
            "KEEP   run2-artifact-b (4.00 MB)",
            "Total artifacts: 6",
            "Retained:        3",
            "Deleted:         3",
            "Space reclaimed: 9.00 MB",
            "Space retained:  10.00 MB",
            "Dry run: 3 artifact(s) would be deleted, reclaiming 9.00 MB",
            # apply step (oldest first):
            "Deleting artifact 'old-build-logs' (workflow run 99)... deleted",
            "Deleting artifact 'run1-artifact-a' (workflow run 100)... deleted",
            "Deleting artifact 'run1-artifact-b' (workflow run 100)... deleted",
            "Deleted 3 artifact(s), reclaimed 9.00 MB",
        ],
    },
    {
        # Nothing violates any policy: everything is retained, both the
        # dry-run and the apply step must be no-ops.
        "name": "nothing-to-delete",
        "now": "2026-07-01T00:00:00Z",
        "artifacts": [
            {"name": "nightly-report", "size_bytes": 1048576,
             "created_at": "2026-06-29T00:00:00Z", "workflow_run_id": 300},
            {"name": "coverage-html", "size_bytes": 2097152,
             "created_at": "2026-06-30T00:00:00Z", "workflow_run_id": 301},
        ],
        "policy": {"max_age_days": 90, "keep_latest_n": 10,
                   "max_total_size_bytes": 1073741824},
        "expected": [
            "KEEP   nightly-report (1.00 MB)",
            "KEEP   coverage-html (2.00 MB)",
            "Total artifacts: 2",
            "Retained:        2",
            "Deleted:         0",
            "Space reclaimed: 0 B",
            "Space retained:  3.00 MB",
            "Dry run: 0 artifact(s) would be deleted, reclaiming 0 B",
            "No artifacts to delete.",
        ],
    },
    {
        # Age-only policy (the other rules are omitted, i.e. disabled):
        # stale-cache (2026-01-01) is 181 days old -> deleted, 5 MB reclaimed.
        "name": "age-only-policy",
        "now": "2026-07-01T00:00:00Z",
        "artifacts": [
            {"name": "stale-cache", "size_bytes": 5242880,
             "created_at": "2026-01-01T00:00:00Z", "workflow_run_id": 1},
            {"name": "fresh-build", "size_bytes": 1048576,
             "created_at": "2026-06-30T00:00:00Z", "workflow_run_id": 2},
        ],
        "policy": {"max_age_days": 30},
        "expected": [
            "DELETE stale-cache (5.00 MB) - max-age: 181 days old exceeds limit of 30 days",
            "KEEP   fresh-build (1.00 MB)",
            "Total artifacts: 2",
            "Retained:        1",
            "Deleted:         1",
            "Space reclaimed: 5.00 MB",
            "Space retained:  1.00 MB",
            "Dry run: 1 artifact(s) would be deleted, reclaiming 5.00 MB",
            "Deleting artifact 'stale-cache' (workflow run 1)... deleted",
            "Deleted 1 artifact(s), reclaimed 5.00 MB",
        ],
    },
]

failures = []


def check(case_name, condition, message):
    """Record (and print) one assertion result."""
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {message}")
    if not condition:
        failures.append(f"{case_name}: {message}")


def build_temp_repo(case, root):
    """Copy the project + this case's fixtures into a fresh git repo."""
    import json
    for name in PROJECT_FILES:
        src = os.path.join(PROJECT_DIR, name)
        dst = os.path.join(root, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    fixtures = os.path.join(root, "fixtures")
    os.makedirs(fixtures)
    with open(os.path.join(fixtures, "artifacts.json"), "w") as fh:
        json.dump(case["artifacts"], fh, indent=2)
    with open(os.path.join(fixtures, "policy.json"), "w") as fh:
        json.dump(case["policy"], fh, indent=2)
    with open(os.path.join(fixtures, "now.txt"), "w") as fh:
        fh.write(case["now"] + "\n")

    env = dict(os.environ,
               GIT_AUTHOR_NAME="harness", GIT_AUTHOR_EMAIL="harness@test",
               GIT_COMMITTER_NAME="harness", GIT_COMMITTER_EMAIL="harness@test")
    for cmd in (["git", "init", "-q"],
                ["git", "add", "-A"],
                ["git", "commit", "-q", "-m", f"fixture: {case['name']}"]):
        subprocess.run(cmd, cwd=root, env=env, check=True,
                       capture_output=True, text=True)


def run_structure_tests():
    """Workflow structure tests (YAML shape, file refs, actionlint)."""
    print("== Workflow structure tests ==")
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "test_workflow_structure", "-v"],
        cwd=PROJECT_DIR, capture_output=True, text=True)
    print(result.stderr.strip().splitlines()[-1])
    check("structure", result.returncode == 0,
          "workflow structure tests (incl. actionlint) exit 0")
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
    return result


def run_case(index, case, result_fh):
    print(f"\n== Case {index}: {case['name']} ==")
    with tempfile.TemporaryDirectory(prefix=f"act-{case['name']}-") as root:
        build_temp_repo(case, root)
        proc = subprocess.run(ACT_CMD, cwd=root, capture_output=True,
                              text=True, timeout=900)
    output = proc.stdout + proc.stderr

    result_fh.write(f"\n{'=' * 78}\n")
    result_fh.write(f"=== CASE {index}: {case['name']} "
                    f"(act exit code {proc.returncode}) ===\n")
    result_fh.write(f"{'=' * 78}\n")
    result_fh.write(output)
    result_fh.flush()

    check(case["name"], proc.returncode == 0, "act exited with code 0")
    for job in JOB_NAMES:
        succeeded = any(
            job in line and "Job succeeded" in line
            for line in output.splitlines())
        check(case["name"], succeeded, f"job '{job}' reports 'Job succeeded'")
    check(case["name"], "Job failed" not in output, "no job reports 'Job failed'")
    for fragment in case["expected"]:
        check(case["name"], fragment in output,
              f"output contains exact value: {fragment!r}")


def main():
    with open(RESULT_FILE, "w") as result_fh:
        result_fh.write("act end-to-end test results\n")
        run_structure_tests()
        for index, case in enumerate(CASES, start=1):
            run_case(index, case, result_fh)
        result_fh.write(f"\n{'=' * 78}\n")
        verdict = "ALL ASSERTIONS PASSED" if not failures else \
            f"{len(failures)} ASSERTION(S) FAILED"
        result_fh.write(f"HARNESS VERDICT: {verdict}\n")
        for failure in failures:
            result_fh.write(f"  FAIL {failure}\n")

    print(f"\n== Verdict: {verdict} (full act output in act-result.txt) ==")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
