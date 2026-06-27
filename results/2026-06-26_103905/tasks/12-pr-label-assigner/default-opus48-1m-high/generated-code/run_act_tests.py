#!/usr/bin/env python3
"""End-to-end test harness: every functional test case runs through the actual
GitHub Actions workflow via ``act`` (nektos/act).

For each test case we:
  1. Build a self-contained temp git repo containing the project files plus the
     case's fixture data (``changed_files.txt`` and, optionally, a custom
     ``rules.json``).
  2. Run ``act push --rm`` against the workflow.
  3. Append the full act output to ``act-result.txt`` (delimited per case).
  4. Assert act exited 0, that BOTH jobs report "Job succeeded", and that the
     workflow emitted the EXACT expected ``LABELS:`` line for that input.

Usage:  python3 run_act_tests.py
Exit code is 0 only if every case passes.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ACT_RESULT = os.path.join(ROOT, "act-result.txt")

# Files copied verbatim into every temp repo.
PROJECT_FILES = ["label_assigner.py", "rules.json", ".actrc"]


# ---------------------------------------------------------------------------
# Test cases. `expected_labels` is the EXACT string the workflow must print on
# its `LABELS:` line for that fixture (see fixtures/*/ for the inputs).
# ---------------------------------------------------------------------------
TEST_CASES = [
    {
        "name": "typical",
        "fixture": "fixtures/typical",
        # docs/intro.md -> documentation; src/api/users.py -> api + python;
        # src/api/users.test.js -> tests (+ api). Ordered by priority desc.
        "expected_labels": "tests,api,documentation,python",
    },
    {
        "name": "no-match",
        "fixture": "fixtures/no-match",
        # LICENSE + Makefile match no rule.
        "expected_labels": "(none)",
    },
    {
        "name": "exclusive-groups",
        "fixture": "fixtures/exclusive-groups",
        # Custom rules.json: size/large beats size/small (same group), plus
        # api and documentation. Ordered by priority desc.
        "expected_labels": "api,documentation,size/large",
    },
]


def build_repo(case: dict, workdir: str) -> None:
    """Materialise a temp git repo for one test case."""
    # Core project files.
    for rel in PROJECT_FILES:
        shutil.copy(os.path.join(ROOT, rel), os.path.join(workdir, rel))
    # Workflow.
    os.makedirs(os.path.join(workdir, ".github", "workflows"), exist_ok=True)
    shutil.copy(
        os.path.join(ROOT, ".github", "workflows", "pr-label-assigner.yml"),
        os.path.join(workdir, ".github", "workflows", "pr-label-assigner.yml"),
    )

    fixture_dir = os.path.join(ROOT, case["fixture"])
    # The fixture's changed-files list becomes the repo's changed_files.txt.
    shutil.copy(
        os.path.join(fixture_dir, "changed_files.txt"),
        os.path.join(workdir, "changed_files.txt"),
    )
    # An optional fixture rules.json overrides the default config.
    fixture_rules = os.path.join(fixture_dir, "rules.json")
    if os.path.isfile(fixture_rules):
        shutil.copy(fixture_rules, os.path.join(workdir, "rules.json"))

    # Initialise git -- act needs a real repo to check out.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    run = lambda *a: subprocess.run(a, cwd=workdir, env=env, check=True,
                                    capture_output=True, text=True)
    run("git", "init", "-q", "-b", "main")
    run("git", "config", "user.email", "ci@example.com")
    run("git", "config", "user.name", "CI")
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", "fixture")


def run_act(workdir: str) -> subprocess.CompletedProcess:
    """Run the workflow via act for a push event."""
    return subprocess.run(
        # --pull=false: the act image is a locally-built image with no registry,
        # so force-pulling it (act's default) fails. Use the local copy.
        ["act", "push", "--rm", "--pull=false"],
        cwd=workdir,
        capture_output=True,
        text=True,
        timeout=600,
    )


def assert_case(case: dict, proc: subprocess.CompletedProcess) -> list[str]:
    """Return a list of failure messages (empty == pass)."""
    failures = []
    output = proc.stdout + "\n" + proc.stderr

    if proc.returncode != 0:
        failures.append(f"act exited {proc.returncode} (expected 0)")

    # Both jobs must succeed.
    success_count = output.count("Job succeeded")
    if success_count < 2:
        failures.append(
            f"expected 2 'Job succeeded' markers, found {success_count}"
        )

    # Exact LABELS line emitted by the script.
    expected_line = f"LABELS: {case['expected_labels']}"
    if expected_line not in output:
        # Surface what we actually saw to aid diagnosis.
        seen = re.findall(r"LABELS:.*", output)
        failures.append(
            f"expected exact line {expected_line!r}; "
            f"saw LABELS lines: {seen!r}"
        )
    return failures


def main() -> int:
    # Fresh result artifact each run.
    with open(ACT_RESULT, "w", encoding="utf-8") as fh:
        fh.write("act-result.txt -- end-to-end workflow runs via nektos/act\n")

    all_passed = True
    for case in TEST_CASES:
        print(f"\n=== Running case: {case['name']} ===", flush=True)
        with tempfile.TemporaryDirectory(prefix=f"act-{case['name']}-") as workdir:
            build_repo(case, workdir)
            try:
                proc = run_act(workdir)
            except subprocess.TimeoutExpired:
                all_passed = False
                with open(ACT_RESULT, "a", encoding="utf-8") as fh:
                    fh.write(f"\n{'=' * 70}\nCASE: {case['name']} -- TIMED OUT\n")
                print(f"  [FAIL] {case['name']}: act timed out")
                continue

            # Persist the full output, clearly delimited.
            with open(ACT_RESULT, "a", encoding="utf-8") as fh:
                fh.write(f"\n{'=' * 70}\n")
                fh.write(f"CASE: {case['name']}\n")
                fh.write(f"FIXTURE: {case['fixture']}\n")
                fh.write(f"EXPECTED LABELS: {case['expected_labels']}\n")
                fh.write(f"ACT EXIT CODE: {proc.returncode}\n")
                fh.write(f"{'-' * 70}\nSTDOUT:\n{proc.stdout}\n")
                fh.write(f"{'-' * 70}\nSTDERR:\n{proc.stderr}\n")

            failures = assert_case(case, proc)
            if failures:
                all_passed = False
                print(f"  [FAIL] {case['name']}:")
                for f in failures:
                    print(f"      - {f}")
            else:
                print(f"  [PASS] {case['name']}: "
                      f"LABELS: {case['expected_labels']}, both jobs succeeded")

    print("\n" + "=" * 40)
    if all_passed:
        print("ALL ACT TEST CASES PASSED")
        print(f"Full output saved to {ACT_RESULT}")
        return 0
    print("SOME ACT TEST CASES FAILED -- see act-result.txt")
    return 1


if __name__ == "__main__":
    sys.exit(main())
