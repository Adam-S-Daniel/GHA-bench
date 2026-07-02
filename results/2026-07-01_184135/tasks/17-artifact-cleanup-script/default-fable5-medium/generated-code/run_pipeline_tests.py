#!/usr/bin/env python3
"""End-to-end pipeline test harness.

Every test case is executed THROUGH the GitHub Actions workflow via act:
for each case we build a throwaway git repo containing the project plus
that case's fixture data, run `act push --rm`, append the output to
act-result.txt, and assert on the exact expected values in the output.

Also runs the workflow structure tests (YAML shape, referenced paths,
actionlint) on the host, since they need the repo and the actionlint
binary rather than a container.
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
RESULT_FILE = REPO_ROOT / "act-result.txt"

# Files each temp repo needs. (fixture + config are case-specific.)
PROJECT_FILES = [
    "artifact_cleanup.py",
    "tests/test_artifact_cleanup.py",
    "tests/test_cli.py",
    ".github/workflows/artifact-cleanup-script.yml",
    ".actrc",
]

# Each case: which fixture/config to install as the repo's live data, and
# the exact strings the act output must contain. Expected values were
# derived by hand from the fixture data (see fixtures/*.json):
#
# case 1 (dry run): nightly-logs-a (800B, 47d old) breaks max-age 30;
#   nightly-logs-b (600B) is the 3rd-newest of workflow run 1 under
#   keep-latest-2; survivors total 1800B <= 2000B budget. Both unit-test
#   files (17 tests) also run inside the pipeline.
# case 2 (execute): total 1600B > 1000B budget, so the oldest survivor
#   cache-v1 (700B) is evicted, leaving 900B; mock deletion is performed.
CASES = [
    {
        "name": "case1-dry-run-combined-policies",
        "artifacts": "fixtures/artifacts.json",
        "config": "cleanup-config.env",
        "expect": [
            "17 passed",  # unit tests inside the pipeline
            "DELETE nightly-logs-a (800 bytes) - exceeds max age of 30 days",
            "DELETE nightly-logs-b (600 bytes) - exceeds keep-latest-2 for workflow run 1",
            "RETAINED_COUNT=3",
            "DELETED_COUNT=2",
            "SPACE_RECLAIMED_BYTES=1400",
            "RETAINED_BYTES=1800",
            "DRY_RUN=true",
        ],
        "forbid": ["Deleted artifact"],  # dry run must not delete
    },
    {
        "name": "case2-execute-size-budget",
        "artifacts": "fixtures/case2-artifacts.json",
        "config": "fixtures/case2-config.env",
        "expect": [
            "17 passed",
            "DELETE cache-v1 (700 bytes) - evicted to satisfy total size budget of 1000 bytes",
            "Deleted artifact 'cache-v1'",
            "RETAINED_COUNT=2",
            "DELETED_COUNT=1",
            "SPACE_RECLAIMED_BYTES=700",
            "RETAINED_BYTES=900",
            "DRY_RUN=false",
        ],
        "forbid": [],
    },
]

JOB_COUNT = 2  # unit-tests + cleanup-plan


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def build_temp_repo(case, tmp):
    """Copy the project + this case's fixture data into tmp and git-commit."""
    for rel in PROJECT_FILES:
        dest = tmp / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO_ROOT / rel, dest)
    (tmp / "fixtures").mkdir(exist_ok=True)
    shutil.copy(REPO_ROOT / case["artifacts"], tmp / "fixtures" / "artifacts.json")
    shutil.copy(REPO_ROOT / case["config"], tmp / "cleanup-config.env")

    def git(*args):
        subprocess.run(
            ["git", *args], cwd=tmp, check=True, capture_output=True,
            env={"PATH": "/usr/bin:/bin", "HOME": str(tmp),
                 "GIT_AUTHOR_NAME": "ci", "GIT_AUTHOR_EMAIL": "ci@test",
                 "GIT_COMMITTER_NAME": "ci", "GIT_COMMITTER_EMAIL": "ci@test"},
        )

    git("init", "-q", "-b", "main")
    git("add", "-A")
    git("commit", "-q", "-m", f"pipeline test {case['name']}")


def run_case(case):
    print(f"=== {case['name']} ===")
    with tempfile.TemporaryDirectory(prefix="act-case-") as tmpdir:
        tmp = Path(tmpdir)
        build_temp_repo(case, tmp)
        result = subprocess.run(
            ["act", "push", "--rm", "--pull=false"],
            cwd=tmp, capture_output=True, text=True, timeout=600,
        )
    output = result.stdout + result.stderr

    with RESULT_FILE.open("a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 70}\n== TEST CASE: {case['name']}\n"
                 f"== exit code: {result.returncode}\n{'=' * 70}\n")
        fh.write(output)

    if result.returncode != 0:
        fail(f"{case['name']}: act exited {result.returncode} (see act-result.txt)")
    for needle in case["expect"]:
        if needle not in output:
            fail(f"{case['name']}: expected string not found: {needle!r}")
    for needle in case["forbid"]:
        if needle in output:
            fail(f"{case['name']}: forbidden string present: {needle!r}")
    succeeded = output.count("Job succeeded")
    if succeeded != JOB_COUNT:
        fail(f"{case['name']}: expected {JOB_COUNT} 'Job succeeded' lines, got {succeeded}")
    if "Job failed" in output:
        fail(f"{case['name']}: a job reported failure")
    print(f"PASS: {case['name']} (exit 0, {succeeded}/{JOB_COUNT} jobs succeeded, "
          f"{len(case['expect'])} exact-value assertions)")


def main():
    RESULT_FILE.write_text("act pipeline test results\n")

    # Workflow structure tests (host-side: YAML shape, paths, actionlint).
    structure = subprocess.run(
        [sys.executable, "-m", "pytest", "tests/test_workflow_structure.py", "-v"],
        cwd=REPO_ROOT,
    )
    if structure.returncode != 0:
        fail("workflow structure tests failed")
    print("PASS: workflow structure tests")

    for case in CASES:
        run_case(case)

    print(f"\nAll pipeline tests passed. Full act output: {RESULT_FILE}")


if __name__ == "__main__":
    main()
