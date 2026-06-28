#!/usr/bin/env python3
"""Integration test harness: every test case runs through the *real* GitHub
Actions workflow via ``act`` (nektos/act).

For each case the harness:
  1. builds a throwaway git repo containing the project files + that case's
     fixture data (copied to ``fixtures/secrets.json``, which the workflow reads),
  2. runs ``act push --rm`` (passing per-case knobs via ``act --env``),
  3. appends the full output to ``act-result.txt`` (a required artifact),
  4. asserts act exited 0,
  5. asserts every job reported "Job succeeded",
  6. parses the workflow output and asserts on EXACT expected values -- the
     per-bucket counts, every secret's status, and the summary line.

The reference date and warning window are injected per case so results are
deterministic and independent of the day the harness runs.

Usage:
  python3 run_act_tests.py                       # run all cases (fresh file)
  python3 run_act_tests.py --only mixed-default  # run a subset
  python3 run_act_tests.py --only a,b --append   # append to act-result.txt
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
ACT_RESULT = os.path.join(PROJECT_ROOT, "act-result.txt")
RUNNER_IMAGE = "act-ubuntu-pwsh:latest"
MARKER = "__ROTATION_REPORT_JSON__"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# Project files copied into each throwaway repo (relative to PROJECT_ROOT).
COPY_PATHS = ["secret_rotation_validator.py", "tests", ".github", ".actrc"]

# ---------------------------------------------------------------------------
# Test cases: each pins a fixture + runtime knobs + the exact expected result.
# ---------------------------------------------------------------------------
CASES = [
    {
        "name": "mixed-default",
        "fixture": "fixtures/cases/mixed.json",
        "env": {"REFERENCE_DATE": "2026-06-28", "WARNING_DAYS": "14"},
        "expected_summary": {"total": 5, "expired": 2, "warning": 1, "ok": 2},
        "expected_statuses": {
            "db-primary-password": "expired",
            "api-signing-key": "expired",
            "tls-cert": "warning",
            "oauth-client-secret": "ok",
            "backup-encryption-key": "ok",
        },
        "expected_summary_line": "SUMMARY expired=2 warning=1 ok=2 total=5",
    },
    {
        # Same fixture, wider warning window -> oauth-client-secret flips
        # ok -> warning. Demonstrates the configurable warning window.
        "name": "mixed-wide-window",
        "fixture": "fixtures/cases/mixed.json",
        "env": {"REFERENCE_DATE": "2026-06-28", "WARNING_DAYS": "120"},
        "expected_summary": {"total": 5, "expired": 2, "warning": 2, "ok": 1},
        "expected_statuses": {
            "db-primary-password": "expired",
            "api-signing-key": "expired",
            "tls-cert": "warning",
            "oauth-client-secret": "warning",
            "backup-encryption-key": "ok",
        },
        "expected_summary_line": "SUMMARY expired=2 warning=2 ok=1 total=5",
    },
    {
        "name": "all-expired",
        "fixture": "fixtures/cases/all_expired.json",
        "env": {"REFERENCE_DATE": "2026-06-28", "WARNING_DAYS": "14"},
        "expected_summary": {"total": 3, "expired": 3, "warning": 0, "ok": 0},
        "expected_statuses": {
            "legacy-root-key": "expired",
            "ci-deploy-token": "expired",
            "smtp-password": "expired",
        },
        "expected_summary_line": "SUMMARY expired=3 warning=0 ok=0 total=3",
    },
]


def strip_ansi(text):
    return ANSI_RE.sub("", text)


def build_repo(case, workdir):
    """Materialise a throwaway git repo for one case and return its path."""
    repo = os.path.join(workdir, "repo")
    os.makedirs(repo)
    for rel in COPY_PATHS:
        src = os.path.join(PROJECT_ROOT, rel)
        dst = os.path.join(repo, rel)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)

    # Place this case's fixture where the workflow expects to read it.
    os.makedirs(os.path.join(repo, "fixtures"), exist_ok=True)
    shutil.copy2(
        os.path.join(PROJECT_ROOT, case["fixture"]),
        os.path.join(repo, "fixtures", "secrets.json"),
    )

    # act/checkout need a real git repo with a commit.
    env = {**os.environ, "GIT_AUTHOR_NAME": "act", "GIT_AUTHOR_EMAIL": "act@test",
           "GIT_COMMITTER_NAME": "act", "GIT_COMMITTER_EMAIL": "act@test"}
    for args in (["init", "-q", "-b", "main"], ["add", "-A"],
                 ["commit", "-q", "-m", "fixture"]):
        subprocess.run(["git", *args], cwd=repo, env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return repo


def run_act(repo, case):
    """Run the workflow for one case through act; return (returncode, output)."""
    cmd = ["act", "push", "--rm", "--pull=false",
           "-P", f"ubuntu-latest={RUNNER_IMAGE}"]
    for key, val in case["env"].items():
        cmd += ["--env", f"{key}={val}"]
    proc = subprocess.run(
        cmd, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=600,
    )
    return proc.returncode, proc.stdout


def parse_report_json(clean_output):
    """Pull the single-line marker JSON back out of the act log."""
    for line in clean_output.splitlines():
        if MARKER in line:
            return json.loads(line.split(MARKER, 1)[1].strip())
    raise AssertionError(f"marker {MARKER!r} not found in act output")


def find_summary_line(clean_output):
    for line in clean_output.splitlines():
        if "SUMMARY expired=" in line:
            return line[line.index("SUMMARY"):].strip()
    raise AssertionError("SUMMARY line not found in act output")


def statuses_from_report(report):
    mapping = {}
    for status, secrets in report["groups"].items():
        for secret in secrets:
            mapping[secret["name"]] = status
    return mapping


def assert_case(case, returncode, clean):
    """Run every assertion for a case; return a list of failure strings."""
    failures = []

    if returncode != 0:
        failures.append(f"act exit code was {returncode}, expected 0")

    succeeded = clean.count("Job succeeded")
    if succeeded < 2:
        failures.append(
            f"expected both jobs to report 'Job succeeded', found {succeeded}"
        )

    if not re.search(r"Ran \d+ tests", clean):
        failures.append("unit test job did not run (no 'Ran N tests' line)")
    if re.search(r"\bFAILED\b", clean):
        failures.append("unit tests reported FAILED")

    # Exact-value assertions on the actual report output.
    try:
        report = parse_report_json(clean)
        if report["summary"] != case["expected_summary"]:
            failures.append(
                f"summary {report['summary']} != expected {case['expected_summary']}"
            )
        actual_statuses = statuses_from_report(report)
        if actual_statuses != case["expected_statuses"]:
            failures.append(
                f"statuses {actual_statuses} != expected {case['expected_statuses']}"
            )
    except AssertionError as exc:
        failures.append(str(exc))

    try:
        summary_line = find_summary_line(clean)
        if summary_line != case["expected_summary_line"]:
            failures.append(
                f"summary line {summary_line!r} != expected "
                f"{case['expected_summary_line']!r}"
            )
    except AssertionError as exc:
        failures.append(str(exc))

    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", help="comma-separated case names to run")
    parser.add_argument("--append", action="store_true",
                        help="append to act-result.txt instead of truncating")
    args = parser.parse_args(argv)

    cases = CASES
    if args.only:
        wanted = {n.strip() for n in args.only.split(",")}
        cases = [c for c in CASES if c["name"] in wanted]
        missing = wanted - {c["name"] for c in cases}
        if missing:
            parser.error(f"unknown case(s): {', '.join(sorted(missing))}")

    mode = "a" if args.append else "w"
    results = []
    with open(ACT_RESULT, mode, encoding="utf-8") as log:
        if not args.append:
            log.write("ACT INTEGRATION TEST RESULTS\n")
            log.write("=" * 70 + "\n")
        for case in cases:
            name = case["name"]
            print(f"\n=== Running case: {name} ===", flush=True)
            with tempfile.TemporaryDirectory() as workdir:
                repo = build_repo(case, workdir)
                try:
                    returncode, output = run_act(repo, case)
                except subprocess.TimeoutExpired:
                    returncode, output = 124, "TIMEOUT: act did not finish in 600s\n"

            clean = strip_ansi(output)
            failures = assert_case(case, returncode, clean)
            ok = not failures
            results.append((name, ok))

            # Persist the full output for this case to the required artifact.
            log.write(f"\n\n{'#' * 70}\n# CASE: {name}\n")
            log.write(f"# env: {case['env']}\n")
            log.write(f"# act exit code: {returncode}\n")
            log.write(f"# verdict: {'PASS' if ok else 'FAIL'}\n")
            if failures:
                log.write("# failures:\n")
                for f in failures:
                    log.write(f"#   - {f}\n")
            log.write("#" * 70 + "\n")
            log.write(clean)
            log.flush()

            if ok:
                print(f"PASS: {name}")
            else:
                print(f"FAIL: {name}")
                for f in failures:
                    print(f"   - {f}")

    print("\n" + "=" * 50)
    passed = sum(1 for _, ok in results if ok)
    for name, ok in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    print(f"{passed}/{len(results)} cases passed")
    print(f"Full output written to {ACT_RESULT}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
