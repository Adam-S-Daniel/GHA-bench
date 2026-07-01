#!/usr/bin/env python3
"""
Outer test harness: actually executes the GitHub Actions workflow through
`act` (nektos/act) in Docker, rather than invoking label_assigner.py
directly. Every functional test case for this task is a *step* inside the
single `pr-label-assigner.yml` workflow (see the "Scenario - ..." steps), so
one `act push --rm` run exercises all of them in one pass -- this keeps us
well under the "at most 3 act push runs" budget while still asserting exact,
per-scenario expected values.

Steps:
  1. Build a throwaway git repo under a temp dir containing the project
     files + fixture data.
  2. Run `act push --rm`, capturing combined stdout/stderr.
  3. Append the captured output to act-result.txt (this repo's cwd), clearly
     delimited.
  4. Assert the process exited 0.
  5. Assert each expected exact label string appears (one per mocked PR
     scenario) and that both jobs report success.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
ACT_RESULT_PATH = REPO_ROOT / "act-result.txt"

# Files/dirs copied into the throwaway git repo that `act` runs against.
PROJECT_ENTRIES = [
    "label_assigner.py",
    "label_rules.json",
    "fixtures",
    "tests",
    ".github",
    ".actrc",
]

# Exact expected values per mocked PR scenario -- these mirror the assertions
# already proven at the unit level in tests/test_label_assigner.py, now
# re-verified as they actually run inside the containerized workflow.
EXPECTED_SCENARIO_OUTPUT = {
    "docs-only PR": "Labels: documentation",
    "api change (priority conflict resolution)": "Labels: api, size/small",
    "mixed changes (multiple independent labels)": "Labels: documentation, size/large, tests",
    "no matching rules": "Labels: (none)",
}

EXPECTED_UNIT_TEST_SUMMARY = "23 passed"


def build_temp_repo() -> Path:
    tmp_dir = Path(tempfile.mkdtemp(prefix="pr-label-assigner-act-"))
    for entry in PROJECT_ENTRIES:
        src = REPO_ROOT / entry
        dst = tmp_dir / entry
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    run(["git", "init", "-q"], cwd=tmp_dir)
    run(["git", "config", "user.email", "act-test@example.com"], cwd=tmp_dir)
    run(["git", "config", "user.name", "act-test"], cwd=tmp_dir)
    run(["git", "add", "-A"], cwd=tmp_dir)
    run(["git", "commit", "-q", "-m", "test commit for act"], cwd=tmp_dir)
    return tmp_dir


def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
    return result


def run_act_push(repo_dir: Path):
    # --pull=false: the custom act-ubuntu-pwsh image is already built locally
    # (see Dockerfile.act); act's default --pull=true tries to re-pull it
    # from a registry and fails with a Docker Hub auth error.
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo_dir, capture_output=True, text=True,
    )


def main() -> int:
    repo_dir = build_temp_repo()
    result = run_act_push(repo_dir)
    combined_output = result.stdout + "\n" + result.stderr

    with open(ACT_RESULT_PATH, "a", encoding="utf-8") as f:
        f.write("=" * 78 + "\n")
        f.write("TEST RUN: pr-label-assigner workflow via `act push --rm`\n")
        f.write(f"Exit code: {result.returncode}\n")
        f.write("=" * 78 + "\n")
        f.write(combined_output)
        f.write("\n")

    shutil.rmtree(repo_dir, ignore_errors=True)

    failures = []

    if result.returncode != 0:
        failures.append(f"act push exited with {result.returncode}, expected 0")

    if EXPECTED_UNIT_TEST_SUMMARY not in combined_output:
        failures.append(f"Expected unit test summary '{EXPECTED_UNIT_TEST_SUMMARY}' not found in act output")

    for scenario, expected_line in EXPECTED_SCENARIO_OUTPUT.items():
        if expected_line not in combined_output:
            failures.append(f"Scenario '{scenario}': expected exact output '{expected_line}' not found")

    success_count = combined_output.count("Job succeeded")
    if success_count < 2:
        failures.append(f"Expected 'Job succeeded' to appear at least twice (one per job), found {success_count}")

    if failures:
        print("ACT TEST HARNESS FAILURES:", file=sys.stderr)
        for f_ in failures:
            print(f" - {f_}", file=sys.stderr)
        return 1

    print("All act-based assertions passed.")
    print(f"Full output appended to {ACT_RESULT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
