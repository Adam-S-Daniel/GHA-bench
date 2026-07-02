#!/usr/bin/env python3
"""End-to-end test harness: every test case runs through the GitHub Actions
workflow via `act` (nektos/act), never by invoking the script directly.

For each case the harness:
  1. builds a temp git repo containing the project plus that case's fixture
     data (fixtures/secrets.json + fixtures/case.env);
  2. runs `act push --rm` in it and captures all output;
  3. appends the output to act-result.txt (clearly delimited);
  4. asserts act exited 0, that BOTH jobs report "Job succeeded", and that
     the output contains the exact expected values for that case's input
     (exact table rows, exact summary counts, exact notification text).

It also runs the host-side workflow structure tests (YAML shape, referenced
paths, actionlint exit code) before touching Docker.
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent
RESULT_FILE = REPO / "act-result.txt"
WORKFLOW = ".github/workflows/secret-rotation-validator.yml"

# Project files copied into each temp repo. Case fixtures overwrite the
# defaults in fixtures/ afterwards.
PROJECT_PATHS = [
    "secret_rotation_validator.py",
    "tests",
    "fixtures",
    ".github",
    ".actrc",
]

# Assertions shared by every case: the unit-test job ran the full TDD suite
# and the validate job proved graceful error handling on fixtures/invalid.json.
COMMON_EXPECTATIONS = [
    "Ran 32 tests",
    "ERROR_HANDLING_OK",
]

CASES = [
    {
        # One secret in each urgency bucket (as of 2026-07-01, warn 14 days).
        "name": "case1-mixed-urgencies",
        "case_env": "AS_OF=2026-07-01\nWARN_DAYS=14\n",
        "secrets": None,  # use the checked-in default fixtures/secrets.json
        "expect": [
            "| db-password | EXPIRED | 2026-01-01 | 2026-04-01 | -91 | billing, api |",
            "| api-key | WARNING | 2026-06-11 | 2026-07-11 | 10 | api |",
            "| tls-cert | OK | 2026-06-30 | 2027-06-30 | 364 | gateway |",
            "ROTATION_SUMMARY: expired=1 warning=1 ok=1",
            "EXPIRED: 'db-password' was due 2026-04-01 (91 days overdue); "
            "rotate immediately. Impacted services: billing, api",
            '"as_of": "2026-07-01"',
            '"warn_days": 14',
        ],
    },
    {
        # Nothing due inside a tighter 7-day window: everything is ok, and
        # rows sort by urgency (fewest days remaining first).
        "name": "case2-all-ok-json",
        "case_env": "AS_OF=2026-07-01\nWARN_DAYS=7\n",
        "secrets": """\
{
  "secrets": [
    {
      "name": "signing-key",
      "last_rotated": "2026-06-15",
      "rotation_days": 60,
      "required_by": ["ci", "deploy"]
    },
    {
      "name": "webhook-token",
      "last_rotated": "2026-07-01",
      "rotation_days": 30,
      "required_by": ["hooks"]
    }
  ]
}
""",
        "expect": [
            "| webhook-token | OK | 2026-07-01 | 2026-07-31 | 30 | hooks |",
            "| signing-key | OK | 2026-06-15 | 2026-08-14 | 44 | ci, deploy |",
            "ROTATION_SUMMARY: expired=0 warning=0 ok=2",
            "OK: 'webhook-token' is due 2026-07-31 (in 30 days).",
            '"warn_days": 7',
            '"expired": 0',
        ],
    },
    {
        # Boundary behaviour: due today => expired; exactly warn_days out
        # => warning; one day beyond the window => ok.
        "name": "case3-boundaries",
        "case_env": "AS_OF=2026-07-01\nWARN_DAYS=14\n",
        "secrets": """\
{
  "secrets": [
    {
      "name": "rotate-today",
      "last_rotated": "2026-06-01",
      "rotation_days": 30,
      "required_by": ["auth"]
    },
    {
      "name": "edge-warning",
      "last_rotated": "2026-06-17",
      "rotation_days": 28,
      "required_by": ["queue"]
    },
    {
      "name": "just-outside",
      "last_rotated": "2026-06-16",
      "rotation_days": 30,
      "required_by": ["cache"]
    }
  ]
}
""",
        "expect": [
            "| rotate-today | EXPIRED | 2026-06-01 | 2026-07-01 | 0 | auth |",
            "| edge-warning | WARNING | 2026-06-17 | 2026-07-15 | 14 | queue |",
            "| just-outside | OK | 2026-06-16 | 2026-07-16 | 15 | cache |",
            "ROTATION_SUMMARY: expired=1 warning=1 ok=1",
            "EXPIRED: 'rotate-today' was due 2026-07-01 (today); "
            "rotate immediately. Impacted services: auth",
        ],
    },
]


def run(cmd, cwd, timeout=None):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
    )


def build_temp_repo(case, tmp):
    """Copy the project into `tmp`, apply case fixtures, git init + commit."""
    for rel in PROJECT_PATHS:
        src = REPO / rel
        if src.is_dir():
            shutil.copytree(src, tmp / rel)
        else:
            shutil.copy2(src, tmp / rel)
    (tmp / "fixtures" / "case.env").write_text(case["case_env"])
    if case["secrets"] is not None:
        (tmp / "fixtures" / "secrets.json").write_text(case["secrets"])
    for git_cmd in (
        ["git", "init", "-q", "-b", "main"],
        ["git", "config", "user.email", "harness@example.com"],
        ["git", "config", "user.name", "Act Harness"],
        ["git", "add", "-A"],
        ["git", "commit", "-qm", f"fixture for {case['name']}"],
    ):
        result = run(git_cmd, cwd=tmp)
        if result.returncode != 0:
            raise RuntimeError(f"{git_cmd} failed: {result.stderr}")


def check_case(case, exit_code, output):
    """Return a list of assertion failure messages (empty = pass)."""
    failures = []
    if exit_code != 0:
        failures.append(f"act exited with {exit_code}, expected 0")

    # Every job must report success, and none may fail.
    for job in ("Unit tests", "Rotation report"):
        if not any(
            job in line and "Job succeeded" in line
            for line in output.splitlines()
        ):
            failures.append(f"no 'Job succeeded' line for job {job!r}")
    if "Job failed" in output:
        failures.append("output contains 'Job failed'")

    for expected in COMMON_EXPECTATIONS + case["expect"]:
        if expected not in output:
            failures.append(f"missing expected output: {expected!r}")
    return failures


def run_structure_tests():
    print("== Workflow structure tests (host) ==")
    result = run(
        [sys.executable, "-m", "unittest", "tests.test_workflow_structure", "-v"],
        cwd=REPO,
    )
    sys.stdout.write(result.stdout + result.stderr)
    return result.returncode == 0, result.stdout + result.stderr


def main():
    all_ok = True
    RESULT_FILE.write_text("")  # start fresh; each case appends

    structure_ok, structure_out = run_structure_tests()
    all_ok &= structure_ok
    with RESULT_FILE.open("a") as log:
        log.write("=" * 78 + "\n")
        log.write("=== HOST: workflow structure tests (incl. actionlint) ===\n")
        log.write("=" * 78 + "\n")
        log.write(structure_out)
        log.write(f"\n--- structure tests {'PASSED' if structure_ok else 'FAILED'} ---\n\n")

    for case in CASES:
        print(f"\n== {case['name']}: running act push --rm ==")
        with tempfile.TemporaryDirectory(prefix=case["name"]) as tmp_name:
            tmp = pathlib.Path(tmp_name)
            build_temp_repo(case, tmp)
            result = run(
                ["act", "push", "--rm", "--pull=false", "-W", WORKFLOW],
                cwd=tmp,
                timeout=600,
            )
        output = result.stdout + result.stderr

        with RESULT_FILE.open("a") as log:
            log.write("=" * 78 + "\n")
            log.write(f"=== ACT CASE: {case['name']} ===\n")
            log.write("=" * 78 + "\n")
            log.write(output)
            log.write(f"\n--- act exit code: {result.returncode} ---\n\n")

        failures = check_case(case, result.returncode, output)
        with RESULT_FILE.open("a") as log:
            if failures:
                log.write(f"--- {case['name']}: FAILED ---\n")
                log.writelines(f"  * {f}\n" for f in failures)
            else:
                log.write(
                    f"--- {case['name']}: PASSED "
                    f"({len(COMMON_EXPECTATIONS + case['expect'])} exact-value "
                    "assertions + 2 job-success assertions) ---\n"
                )
            log.write("\n")

        if failures:
            all_ok = False
            print(f"FAILED: {case['name']}")
            for failure in failures:
                print(f"  * {failure}")
        else:
            print(f"PASSED: {case['name']}")

    print(f"\nFull act output written to {RESULT_FILE}")
    print("RESULT:", "ALL PASSED" if all_ok else "FAILURES DETECTED")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
