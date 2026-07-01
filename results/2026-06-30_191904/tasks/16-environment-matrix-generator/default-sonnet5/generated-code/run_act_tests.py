#!/usr/bin/env python3
"""
Integration test harness -- exercises the full GitHub Actions workflow
(.github/workflows/environment-matrix-generator.yml) through `act`, once
per test-case fixture. This is where matrix_generator.py's *behavior* is
actually validated: the generated matrix JSON is asserted against known-good
expected values parsed straight out of the `act push` output, never by
calling matrix_generator.py directly.

For each test case, this script:
  1. Creates an isolated temp git repo containing a copy of the project.
  2. Overwrites matrix-config.json (the workflow's default input, since
     `act push` fires the `push` event and workflow_dispatch inputs are
     unavailable) with that case's fixture content. This file is
     deliberately separate from fixtures/*.json, which the unit test
     suite loads by exact name -- swapping the active config must never
     corrupt the fixtures the tests themselves depend on.
  3. Commits the repo.
  4. Runs `act push --rm`, capturing combined stdout/stderr.
  5. Appends the output to act-result.txt (delimited per case).
  6. Asserts the process exited 0.
  7. Asserts the exact expected matrix JSON appears in the captured output.
  8. Asserts every job reports success.

Usage: python3 run_act_tests.py
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
RESULT_FILE = PROJECT_ROOT / "act-result.txt"

FILES_TO_COPY = [
    "matrix_generator.py",
    "conftest.py",
    "tests",
    "fixtures",
    "matrix-config.json",
    ".github",
    ".actrc",
]

# Each case's expected_include is the known-good result of hand-tracing
# build_matrix() over that fixture (also covered by the unit tests in
# tests/test_matrix_generator.py) -- here it is re-verified end-to-end
# through the real GitHub Actions pipeline running inside Docker via act.
CASES = [
    {
        "name": "config_basic",
        "fixture": "fixtures/config_basic.json",
        "expected_matrix": {
            "strategy": {
                "fail-fast": False,
                "max-parallel": 4,
                "matrix": {
                    "include": [
                        {"os": "ubuntu-latest", "python_version": "3.10"},
                        {"os": "ubuntu-latest", "python_version": "3.11"},
                        {"os": "windows-latest", "python_version": "3.11"},
                        {"os": "ubuntu-latest", "python_version": "3.12", "experimental": True},
                    ]
                },
            }
        },
    },
    {
        "name": "config_include_merge",
        "fixture": "fixtures/config_include_merge.json",
        "expected_matrix": {
            "strategy": {
                "fail-fast": True,
                "max-parallel": 2,
                "matrix": {
                    "include": [
                        {"os": "ubuntu-latest", "node_version": "18"},
                        {"os": "ubuntu-latest", "node_version": "20", "coverage": True},
                        {"os": "macos-latest", "node_version": "18"},
                        {"os": "macos-latest", "node_version": "20"},
                    ]
                },
            }
        },
    },
]

# act renders each job by its display `name:`, not its YAML key.
JOB_NAMES = ["Run unit tests", "Generate build matrix", "Use generated matrix"]


def _setup_temp_repo(case):
    tmp_dir = Path(tempfile.mkdtemp(prefix=f"act-test-{case['name']}-"))
    for item in FILES_TO_COPY:
        src = PROJECT_ROOT / item
        dst = tmp_dir / item
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    case_fixture_src = PROJECT_ROOT / case["fixture"]
    active_config_dst = tmp_dir / "matrix-config.json"
    shutil.copy2(case_fixture_src, active_config_dst)

    subprocess.run(["git", "init", "-q"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.email", "act-harness@example.com"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "config", "user.name", "act-harness"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp_dir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", f"test: {case['name']}"], cwd=tmp_dir, check=True)
    return tmp_dir


def _run_act(tmp_dir):
    return subprocess.run(
        # --pull=false: the custom act-ubuntu-pwsh:latest image is only
        # available locally (pre-built for this environment); act's default
        # forced pull would try (and fail) to fetch it from a registry.
        ["act", "push", "--rm", "--pull=false"],
        cwd=tmp_dir,
        capture_output=True,
        text=True,
        timeout=600,
    )


def run_case(case):
    print(f"=== Running test case: {case['name']} ===", flush=True)
    tmp_dir = _setup_temp_repo(case)
    try:
        proc = _run_act(tmp_dir)
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

    combined_output = proc.stdout + "\n" + proc.stderr

    with open(RESULT_FILE, "a") as f:
        f.write(f"\n{'=' * 80}\n")
        f.write(f"TEST CASE: {case['name']}\n")
        f.write(f"FIXTURE: {case['fixture']}\n")
        f.write(f"EXIT CODE: {proc.returncode}\n")
        f.write(f"{'=' * 80}\n")
        f.write(combined_output)
        f.write("\n")

    failures = []

    if proc.returncode != 0:
        failures.append(f"act push exited {proc.returncode}, expected 0")

    # act right-pads job-name prefixes with trailing spaces to align them
    # against the longest job name seen so far (e.g. "[.../Use generated
    # matrix ]"), so match on the job name as a loose substring rather
    # than an exact "[workflow/job]" bracket string.
    for job_name in JOB_NAMES:
        if job_name not in combined_output:
            failures.append(f"job '{job_name}' never appeared in act output")

    if "Job failed" in combined_output:
        failures.append("at least one job reported 'Job failed'")

    succeeded_count = combined_output.count("Job succeeded")
    if succeeded_count != len(JOB_NAMES):
        failures.append(
            f"expected {len(JOB_NAMES)} 'Job succeeded' lines (one per job), got {succeeded_count}"
        )

    # Exact-value assertion: the matrix JSON printed between the
    # generate-matrix step's markers must equal the known-good expected
    # matrix for this fixture -- not just "some JSON appeared". act
    # prefixes every line of step output with "[workflow/job]   | ", so
    # that prefix has to be stripped per-line before the marker region
    # can be parsed back into JSON.
    act_line_prefix_re = re.compile(r"^\[[^\]]*\]\s*(?:\|\s*)?")
    cleaned_lines = [act_line_prefix_re.sub("", line) for line in combined_output.splitlines()]

    start_marker = "----MATRIX-JSON-START----"
    end_marker = "----MATRIX-JSON-END----"
    try:
        start_idx = cleaned_lines.index(start_marker)
        end_idx = cleaned_lines.index(end_marker)
    except ValueError:
        start_idx = end_idx = -1

    if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
        failures.append("matrix JSON markers not found in act output")
    else:
        json_text = "\n".join(cleaned_lines[start_idx + 1:end_idx]).strip()
        try:
            actual_matrix = json.loads(json_text)
        except json.JSONDecodeError as e:
            failures.append(f"could not parse matrix JSON from act output: {e}")
            actual_matrix = None

        if actual_matrix is not None and actual_matrix != case["expected_matrix"]:
            failures.append(
                f"matrix JSON mismatch.\nExpected: {json.dumps(case['expected_matrix'])}\n"
                f"Actual:   {json.dumps(actual_matrix)}"
            )

    if failures:
        print(f"FAIL [{case['name']}]:")
        for msg in failures:
            print(f"  - {msg}")
        return False

    print(f"PASS [{case['name']}]")
    return True


def main():
    if RESULT_FILE.exists():
        RESULT_FILE.unlink()

    results = [run_case(case) for case in CASES]

    print()
    print(f"{sum(results)}/{len(results)} test cases passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
