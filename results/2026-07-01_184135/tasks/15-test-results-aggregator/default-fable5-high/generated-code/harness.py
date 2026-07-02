#!/usr/bin/env python3
"""End-to-end CI harness: runs every test case THROUGH the GitHub Actions
workflow via `act` (nektos/act), never by invoking aggregator.py directly.

For each test case it:
  1. creates a temp git repo containing the project files plus that case's
     fixture data in `test-results/` (the directory the workflow consumes),
  2. runs `act push --rm` against the repo,
  3. appends the full act output to ./act-result.txt (clearly delimited),
  4. asserts act exited 0, that BOTH workflow jobs report "Job succeeded",
     and that the output contains the case's EXACT expected values
     (totals line, flaky test ids, markdown cells) — known-good numbers
     hand-computed from the fixture files.

It also runs the workflow *structure* tests (YAML shape + actionlint) locally
before spending time on act runs.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ACT_RESULT = ROOT / "act-result.txt"
ACT_IMAGE = "act-ubuntu-pwsh:latest"

# Files/dirs copied into each temp repo (the project under test).
PROJECT_ITEMS = ["aggregator.py", "tests", "fixtures", ".github", ".actrc"]

# Each case: fixture source dir -> exact strings that MUST appear in act
# output. Totals are hand-computed from the fixtures:
#   case1: ubuntu(2p/1f/1s, 3.5s) + windows(2p/1f/1s, 3.6s) + macos(3p/1f/0s, 4.0s)
#          => total=12 passed=7 failed=3 skipped=2 duration=11.10, 2 flaky tests
#   case2: junit-a(3p, 0.6s) + results-b(2p/1s, 0.9s)
#          => total=6 passed=5 failed=0 skipped=1 duration=1.50, no flaky tests
CASES = [
    {
        "name": "case1-matrix-flaky",
        "fixtures": "fixtures/case1-matrix-flaky",
        "expect": [
            "RESULT total=12 passed=7 failed=3 skipped=2 duration=11.10 flaky=2",
            "FLAKY shop.tests::test_checkout",
            "FLAKY shop.tests::test_flaky_search",
            "| **Total** | **12** |",
            "| `shop.tests::test_checkout` | junit-ubuntu.xml | junit-windows.xml, results-macos.json |",
            "Aggregating results from: test-results",
        ],
    },
    {
        "name": "case2-all-green",
        "fixtures": "fixtures/case2-all-green",
        "expect": [
            "RESULT total=6 passed=5 failed=0 skipped=1 duration=1.50 flaky=0",
            "No flaky tests detected",
            "| **Total** | **6** |",
            "| ✅ Passed | 5 |",
            "Aggregating results from: test-results",
        ],
    },
]

# act reports success per job using the workflow/job display names.
EXPECTED_JOB_SUCCESS = [
    "[Test Results Aggregator/Unit tests",
    "[Test Results Aggregator/Aggregate test results",
]


def run(cmd: list[str], cwd: Path, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)


def check(condition: bool, label: str, failures: list[str]) -> None:
    print(("  PASS  " if condition else "  FAIL  ") + label)
    if not condition:
        failures.append(label)


def run_structure_tests(failures: list[str]) -> None:
    """Workflow structure tests: YAML shape, referenced paths, actionlint."""
    print("== Workflow structure tests (local) ==")
    proc = run([sys.executable, "-m", "unittest",
                "tests.test_workflow_structure", "-v"], cwd=ROOT)
    print(proc.stdout)
    check(proc.returncode == 0, "structure tests (unittest) exit code 0", failures)

    lint = run(["actionlint", ".github/workflows/test-results-aggregator.yml"], cwd=ROOT)
    if lint.stdout.strip():
        print(lint.stdout)
    check(lint.returncode == 0, "actionlint exit code 0", failures)


def run_case(case: dict, failures: list[str]) -> None:
    print(f"== act test case: {case['name']} ==")
    with tempfile.TemporaryDirectory(prefix=f"agg-{case['name']}-") as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        # Project files + this case's fixture data as test-results/.
        for item in PROJECT_ITEMS:
            src = ROOT / item
            if src.is_dir():
                shutil.copytree(src, repo / item)
            else:
                shutil.copy2(src, repo / item)
        shutil.copytree(ROOT / case["fixtures"], repo / "test-results")

        for cmd in (["git", "init", "-q"],
                    ["git", "config", "user.email", "harness@example.com"],
                    ["git", "config", "user.name", "Harness"],
                    ["git", "add", "-A"],
                    ["git", "commit", "-q", "-m", f"harness: {case['name']}"]):
            proc = run(cmd, cwd=repo)
            if proc.returncode != 0:
                failures.append(f"{case['name']}: git setup failed: {proc.stdout}")
                return

        proc = run(
            ["act", "push", "--rm", "--pull=false",
             "-P", f"ubuntu-latest={ACT_IMAGE}"],
            cwd=repo, timeout=480,
        )
        output = proc.stdout

    with ACT_RESULT.open("a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 78}\n=== ACT TEST CASE: {case['name']} "
                 f"(exit code {proc.returncode}) ===\n{'=' * 78}\n")
        fh.write(output)

    check(proc.returncode == 0, f"{case['name']}: act exit code 0", failures)
    for marker in EXPECTED_JOB_SUCCESS:
        ok = any(marker in line and "Job succeeded" in line
                 for line in output.splitlines())
        check(ok, f"{case['name']}: job succeeded: {marker}]", failures)
    for expected in case["expect"]:
        check(expected in output, f"{case['name']}: output contains {expected!r}", failures)


def main() -> int:
    failures: list[str] = []
    ACT_RESULT.write_text(
        "act harness results — every test case executed through the GitHub "
        "Actions workflow via `act push --rm`\n", encoding="utf-8")

    run_structure_tests(failures)
    for case in CASES:
        run_case(case, failures)

    print("\n== HARNESS SUMMARY ==")
    if failures:
        print(f"{len(failures)} assertion(s) FAILED:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("All harness assertions passed "
          f"({len(CASES)} act cases + structure tests). See {ACT_RESULT.name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
