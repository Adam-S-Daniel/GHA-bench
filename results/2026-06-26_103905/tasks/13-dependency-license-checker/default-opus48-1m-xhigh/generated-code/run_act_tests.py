#!/usr/bin/env python3
"""End-to-end test harness: run every scenario through the GitHub Actions
workflow via ``act`` (nektos/act) in Docker.

Per the task, *all functional test cases run through the pipeline* -- not the
script directly.  For each case this harness:

1. Creates a throwaway git repo containing the project files + that case's
   fixture data (manifest + mock license database).
2. Commits and runs ``act push --rm`` against the real workflow.
3. Appends the full act output to ``act-result.txt`` (the required artifact),
   clearly delimited per case.
4. Asserts ``act`` exited 0, that BOTH jobs report "Job succeeded", and that the
   workflow produced the EXACT expected compliance summary + per-dependency
   status line for that case's known input.

Budget discipline: if a case's ``act`` invocation fails at the infrastructure
level (non-zero exit), we stop immediately rather than burning the remaining
runs on an identical workflow -- diagnose from the saved output, fix, re-run.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
ACT_RESULT = os.path.join(REPO, "act-result.txt")

# The allow/deny policy is constant across cases; only the manifest + license
# database vary, which is what makes each case's expected output deterministic.
POLICY = json.load(open(os.path.join(REPO, "fixtures", "policy.json"), encoding="utf-8"))


# Each case = (manifest dependencies, mock license DB, expected summary line,
# an expected per-dependency status line that proves the classification).
CASES = [
    {
        "name": "all-approved",
        "manifest": {
            "name": "case-a",
            "version": "1.0.0",
            "dependencies": {"left-pad": "1.3.0", "lodash": "^4.17.21", "react": "18.2.0"},
        },
        # mixes name@version and bare-name keys to exercise both lookup paths
        "licenses": {"left-pad@1.3.0": "MIT", "lodash": "MIT", "react": "MIT"},
        "expect_summary": "LICENSE-CHECK-SUMMARY total=3 approved=3 denied=0 unknown=0",
        "expect_line": "left-pad@1.3.0: MIT [approved]",
    },
    {
        "name": "denied-present",
        "manifest": {
            "name": "case-b",
            "version": "1.0.0",
            "dependencies": {"left-pad": "1.3.0", "copyleft-lib": "2.0.0", "lodash": "^4.17.21"},
        },
        "licenses": {"left-pad": "MIT", "copyleft-lib": "GPL-3.0", "lodash": "MIT"},
        "expect_summary": "LICENSE-CHECK-SUMMARY total=3 approved=2 denied=1 unknown=0",
        "expect_line": "copyleft-lib@2.0.0: GPL-3.0 [denied]",
    },
    {
        "name": "unknown-license",
        "manifest": {
            "name": "case-c",
            "version": "1.0.0",
            "dependencies": {"left-pad": "1.3.0", "mystery-pkg": "0.1.0"},
        },
        # mystery-pkg deliberately absent from the DB -> classified unknown
        "licenses": {"left-pad": "MIT"},
        "expect_summary": "LICENSE-CHECK-SUMMARY total=2 approved=1 denied=0 unknown=1",
        "expect_line": "mystery-pkg@0.1.0: UNKNOWN [unknown]",
    },
]


def _build_repo(tmp, case):
    """Populate *tmp* with the project files + this case's fixture data."""
    # Project source needed by the workflow.
    shutil.copy(os.path.join(REPO, "license_checker.py"), tmp)
    shutil.copy(os.path.join(REPO, ".actrc"), tmp)  # selects the local act image
    shutil.copytree(os.path.join(REPO, "tests"), os.path.join(tmp, "tests"))
    shutil.copytree(os.path.join(REPO, ".github"), os.path.join(tmp, ".github"))

    # Fixtures: constant policy + this case's manifest and mock license DB.
    fx = os.path.join(tmp, "fixtures")
    os.makedirs(fx, exist_ok=True)
    with open(os.path.join(fx, "policy.json"), "w", encoding="utf-8") as fh:
        json.dump(POLICY, fh)
    with open(os.path.join(fx, "package.json"), "w", encoding="utf-8") as fh:
        json.dump(case["manifest"], fh)
    with open(os.path.join(fx, "licenses.json"), "w", encoding="utf-8") as fh:
        json.dump(case["licenses"], fh)


def _git_commit(tmp):
    env = dict(os.environ, GIT_AUTHOR_NAME="ci", GIT_AUTHOR_EMAIL="ci@example.com",
               GIT_COMMITTER_NAME="ci", GIT_COMMITTER_EMAIL="ci@example.com")
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=tmp, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=tmp, check=True, env=env)
    subprocess.run(["git", "commit", "-q", "-m", "scenario fixture"], cwd=tmp, check=True, env=env)


def _run_act(tmp):
    """Run the workflow via act; return (exit_code, combined_output)."""
    # Pin the platform explicitly (last -P wins) to the locally-present image so
    # act never tries to pull a non-local image referenced by a global ~/.actrc.
    proc = subprocess.run(
        ["act", "push", "--rm", "--pull=false",
         "-P", "ubuntu-latest=act-ubuntu-pwsh:latest"],
        cwd=tmp,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=420,
    )
    return proc.returncode, proc.stdout


def _append_result(case_name, exit_code, output):
    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write("=" * 78 + "\n")
        fh.write(f"TEST CASE: {case_name}\n")
        fh.write(f"act exit code: {exit_code}\n")
        fh.write("-" * 78 + "\n")
        fh.write(output)
        if not output.endswith("\n"):
            fh.write("\n")
        fh.write("\n")


def _assert(cond, msg, failures):
    if not cond:
        failures.append(msg)
        print(f"    FAIL: {msg}")
    else:
        print(f"    ok:   {msg}")


def main():
    # Fresh artifact each run.
    if os.path.exists(ACT_RESULT):
        os.remove(ACT_RESULT)

    all_failures = []
    for case in CASES:
        name = case["name"]
        print(f"\n=== CASE: {name} ===")
        tmp = tempfile.mkdtemp(prefix=f"act-{name}-")
        try:
            _build_repo(tmp, case)
            _git_commit(tmp)
            try:
                exit_code, output = _run_act(tmp)
            except subprocess.TimeoutExpired as exc:
                output = (exc.output or b"")
                output = output.decode() if isinstance(output, bytes) else (exc.stdout or "")
                exit_code = 124
            _append_result(name, exit_code, output)

            failures = []
            _assert(exit_code == 0, f"act exited 0 (got {exit_code})", failures)
            # Infra failure -> stop before spending more act runs on the same workflow.
            if exit_code != 0:
                all_failures.extend(f"[{name}] {m}" for m in failures)
                print("    act failed at infra level; aborting remaining cases "
                      "to preserve the act-run budget. See act-result.txt.")
                break

            jobs_succeeded = output.count("Job succeeded")
            _assert(jobs_succeeded == 2,
                    f"both jobs report 'Job succeeded' (got {jobs_succeeded})", failures)
            _assert(case["expect_summary"] in output,
                    f"exact summary present: {case['expect_summary']!r}", failures)
            _assert(case["expect_line"] in output,
                    f"exact status line present: {case['expect_line']!r}", failures)
            all_failures.extend(f"[{name}] {m}" for m in failures)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    print("\n" + "=" * 60)
    if all_failures:
        print(f"RESULT: FAILED ({len(all_failures)} assertion(s))")
        for f in all_failures:
            print(f"  - {f}")
        return 1
    print("RESULT: PASSED -- all scenarios verified through act.")
    print(f"Artifact written: {ACT_RESULT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
