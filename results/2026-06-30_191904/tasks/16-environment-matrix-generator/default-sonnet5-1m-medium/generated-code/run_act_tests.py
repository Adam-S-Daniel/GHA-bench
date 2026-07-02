#!/usr/bin/env python3
"""
Act-based integration test harness.

Per project requirements, every test case must be exercised end-to-end
through the real GitHub Actions workflow via `act`, not by calling
matrix_generator.py directly. For each test case this script:

  1. Creates an isolated temp directory containing a copy of the project
     (script, tests, workflow, fixtures) plus that case's fixture data for
     fixtures/ci_matrix.json (the file the workflow's generate-matrix job
     reads).
  2. Initializes a throwaway git repo there (act needs a git repo) and
     commits the files.
  3. Runs `act push --rm` inside that repo and captures combined output.
  4. Appends the output to act-result.txt (in the original working
     directory), clearly delimited per test case.
  5. Asserts exit code 0, asserts every job reports "Job succeeded", and
     asserts the output contains the exact expected matrix values for that
     case's input config.

Run with: python3 run_act_tests.py
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
RESULT_FILE = ROOT / "act-result.txt"

PROJECT_FILES = [
    "matrix_generator.py",
    "test_matrix_generator.py",
    "test_workflow_structure.py",
    ".actrc",
]
PROJECT_DIRS = [
    "fixtures",
    ".github",
]

# Each case overrides fixtures/ci_matrix.json (the file the workflow's
# generate-matrix job actually reads) with different config, then asserts
# the exact resulting matrix/fail-fast/max-parallel values appear in the
# act output.
CASES = [
    {
        "name": "two-python-versions-fail-fast",
        "config": {
            "dimensions": {
                "os": ["ubuntu-latest"],
                "python-version": ["3.10", "3.11"],
            },
            "fail_fast": True,
            "max_parallel": 2,
            "max_size": 10,
        },
        "expected_strategy_json": json.dumps(
            {
                "fail-fast": True,
                "max-parallel": 2,
                "matrix": {
                    "include": [
                        {"os": "ubuntu-latest", "python-version": "3.10"},
                        {"os": "ubuntu-latest", "python-version": "3.11"},
                    ]
                },
            }
        ),
        "expected_job_count": 2,  # build (3.10), build (3.11)
    },
    {
        "name": "include-merge-three-versions",
        "config": {
            "dimensions": {
                "os": ["ubuntu-latest"],
                "python-version": ["3.10", "3.11", "3.12"],
            },
            "include": [
                {"os": "ubuntu-latest", "python-version": "3.12", "experimental": True}
            ],
            "fail_fast": False,
            "max_parallel": 2,
            "max_size": 10,
        },
        "expected_strategy_json": json.dumps(
            {
                "fail-fast": False,
                "max-parallel": 2,
                "matrix": {
                    "include": [
                        {"os": "ubuntu-latest", "python-version": "3.10"},
                        {"os": "ubuntu-latest", "python-version": "3.11"},
                        {
                            "os": "ubuntu-latest",
                            "python-version": "3.12",
                            "experimental": True,
                        },
                    ]
                },
            }
        ),
        "expected_job_count": 3,  # build (3.10), build (3.11), build (3.12)
    },
]


def setup_case_repo(tmp_dir: Path, case: dict) -> None:
    for name in PROJECT_FILES:
        shutil.copy2(ROOT / name, tmp_dir / name)
    for name in PROJECT_DIRS:
        shutil.copytree(ROOT / name, tmp_dir / name)

    # Overwrite the fixture the workflow actually reads with this case's
    # config, so a single workflow file drives every test case.
    fixture_path = tmp_dir / "fixtures" / "ci_matrix.json"
    fixture_path.write_text(json.dumps(case["config"], indent=2) + "\n")

    subprocess.run(["git", "init", "-q"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.name", "Test Harness"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "test fixture commit"], cwd=tmp_dir, check=True)


def run_act(tmp_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=tmp_dir,
        capture_output=True,
        text=True,
        timeout=600,
    )


def run_case(case: dict) -> None:
    print(f"=== Running act test case: {case['name']} ===")
    with tempfile.TemporaryDirectory(prefix="matrix-gen-act-") as tmp:
        tmp_dir = Path(tmp)
        setup_case_repo(tmp_dir, case)
        proc = run_act(tmp_dir)

    combined_output = proc.stdout + "\n" + proc.stderr

    with open(RESULT_FILE, "a", encoding="utf-8") as f:
        f.write(f"\n{'=' * 80}\nTEST CASE: {case['name']}\n{'=' * 80}\n")
        f.write(f"Exit code: {proc.returncode}\n\n")
        f.write(combined_output)
        f.write("\n")

    assert proc.returncode == 0, (
        f"[{case['name']}] act exited with {proc.returncode}, expected 0:\n{combined_output}"
    )

    job_success_count = combined_output.count("Job succeeded")
    # 1 unit-tests + 1 generate-matrix + N build (one per matrix entry)
    expected_success_count = 2 + case["expected_job_count"]
    assert job_success_count == expected_success_count, (
        f"[{case['name']}] expected {expected_success_count} 'Job succeeded' "
        f"occurrences, found {job_success_count}:\n{combined_output}"
    )

    assert case["expected_strategy_json"] in combined_output, (
        f"[{case['name']}] expected exact strategy JSON not found in act output.\n"
        f"Expected: {case['expected_strategy_json']}\n"
        f"Output:\n{combined_output}"
    )

    print(f"=== PASSED: {case['name']} ===\n")


def main() -> int:
    if RESULT_FILE.exists():
        RESULT_FILE.unlink()

    failures = []
    for case in CASES:
        try:
            run_case(case)
        except AssertionError as exc:
            failures.append(str(exc))
            print(f"=== FAILED: {case['name']} ===\n{exc}\n", file=sys.stderr)

    if failures:
        print(f"\n{len(failures)} of {len(CASES)} act test case(s) failed.", file=sys.stderr)
        return 1

    print(f"\nAll {len(CASES)} act test cases passed. See {RESULT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
