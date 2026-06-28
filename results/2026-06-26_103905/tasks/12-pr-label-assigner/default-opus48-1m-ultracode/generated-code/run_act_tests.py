#!/usr/bin/env python3
"""Act integration harness for the PR Label Assigner workflow.

This is the "all test cases run through the pipeline" requirement: every case
is executed by the real GitHub Actions workflow inside Docker via `act`, not by
calling the script directly.

For each fixture case it:
  1. builds a throwaway git repo containing the project files + that case's
     changed_files.txt,
  2. runs `act push --rm`,
  3. appends the full, delimited output to ./act-result.txt,
  4. asserts act exited 0, the workflow printed the EXACT expected
     RESULT_LABELS / RESULT_COUNT, and every job reports "Job succeeded".

Run it directly:  python3 run_act_tests.py
Exit code is 0 only if every case passes.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ACT_RESULT = os.path.join(ROOT, "act-result.txt")
IMAGE = "act-ubuntu-pwsh:latest"

# Files that make up the project inside each temp repo.
PROJECT_FILES = [
    "pr_label_assigner.py",
    ".github/workflows/pr-label-assigner.yml",
    ".actrc",
    "label-rules.json",
]

CASES = ["case1", "case2", "case3"]


def _run(cmd, cwd, timeout=300):
    """Run a command, returning (returncode, combined_output)."""
    proc = subprocess.run(
        cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=timeout,
    )
    return proc.returncode, proc.stdout


def _setup_repo(case):
    """Create a temp git repo with project files + this case's fixture."""
    workdir = tempfile.mkdtemp(prefix=f"pr-label-{case}-")

    for rel in PROJECT_FILES:
        src = os.path.join(ROOT, rel)
        dst = os.path.join(workdir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)

    # A case may override the rules; otherwise the root config is reused.
    case_rules = os.path.join(ROOT, "fixtures", case, "label-rules.json")
    if os.path.isfile(case_rules):
        shutil.copy2(case_rules, os.path.join(workdir, "label-rules.json"))

    # The case's changed-files list becomes the repo's mock PR file list.
    shutil.copy2(
        os.path.join(ROOT, "fixtures", case, "changed_files.txt"),
        os.path.join(workdir, "changed_files.txt"),
    )

    # Minimal committed git repo (act needs a commit to drive `push`).
    for cmd in (
        ["git", "init", "-q", "-b", "main"],
        ["git", "config", "user.email", "ci@example.com"],
        ["git", "config", "user.name", "CI"],
        ["git", "add", "-A"],
        ["git", "commit", "-q", "-m", f"fixture {case}"],
    ):
        rc, out = _run(cmd, workdir, timeout=60)
        if rc != 0:
            raise RuntimeError(f"git setup failed ({cmd}):\n{out}")
    return workdir


def _expected(case):
    with open(os.path.join(ROOT, "fixtures", case, "expected.json")) as fh:
        return json.load(fh)


def _parse_last(pattern, text):
    """Return the last capture of `pattern` in `text`, or None."""
    matches = re.findall(pattern, text)
    return matches[-1] if matches else None


def run_case(case, log):
    """Execute one case through act and assert on the result. Returns bool."""
    expected = _expected(case)
    workdir = _setup_repo(case)
    try:
        # Pass -P explicitly (in addition to the copied .actrc) and disable
        # image pulls — the custom image is already present locally.
        rc, output = _run(
            ["act", "push", "--rm", "--pull=false", "-P", f"ubuntu-latest={IMAGE}"],
            workdir, timeout=300,
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    # --- persist the artifact (delimited per case) -------------------------
    log.write(f"\n{'=' * 70}\n")
    log.write(f"TEST CASE: {case}\n")
    log.write(f"Expected RESULT_LABELS={expected['result_labels']} "
              f"(count={expected['count']})\n")
    log.write(f"act exit code: {rc}\n")
    log.write(f"{'-' * 70}\n")
    log.write(output)
    log.write(f"\n{'=' * 70}\n")
    log.flush()

    # --- assertions --------------------------------------------------------
    ok = True

    def check(cond, msg):
        nonlocal ok
        status = "PASS" if cond else "FAIL"
        print(f"  [{status}] {msg}")
        log.write(f"ASSERT [{status}] {msg}\n")
        ok = ok and cond

    check(rc == 0, f"act exited 0 (got {rc})")

    got_labels = _parse_last(r"RESULT_LABELS=(\S*)", output)
    # An empty label set prints "RESULT_LABELS=" with nothing after; normalise.
    if got_labels is None and "RESULT_LABELS=" in output:
        got_labels = ""
    check(got_labels == expected["result_labels"],
          f"RESULT_LABELS == '{expected['result_labels']}' (got '{got_labels}')")

    got_count = _parse_last(r"RESULT_COUNT=(\d+)", output)
    check(got_count == str(expected["count"]),
          f"RESULT_COUNT == {expected['count']} (got {got_count})")

    check("Job succeeded" in output, "workflow reported 'Job succeeded'")

    log.write(f"CASE {case}: {'PASS' if ok else 'FAIL'}\n")
    log.flush()
    return ok


def main():
    if shutil.which("act") is None:
        print("ERROR: act is not installed", file=sys.stderr)
        return 3
    if shutil.which("docker") is None:
        print("ERROR: docker is not installed", file=sys.stderr)
        return 3

    print(f"Running {len(CASES)} cases through act -> {ACT_RESULT}")
    with open(ACT_RESULT, "w", encoding="utf-8") as log:
        log.write("PR Label Assigner — act integration results\n")
        results = {}
        for case in CASES:
            print(f"\n=== {case} ===")
            try:
                results[case] = run_case(case, log)
            except Exception as exc:  # noqa: BLE001 - surface any harness error
                print(f"  [FAIL] harness error: {exc}")
                log.write(f"CASE {case}: HARNESS ERROR: {exc}\n")
                results[case] = False

        log.write("\n" + "=" * 70 + "\nSUMMARY\n")
        for case, passed in results.items():
            log.write(f"  {case}: {'PASS' if passed else 'FAIL'}\n")

    passed = sum(1 for v in results.values() if v)
    print(f"\nSummary: {passed}/{len(CASES)} cases passed. "
          f"Full log: {ACT_RESULT}")
    return 0 if passed == len(CASES) else 1


if __name__ == "__main__":
    sys.exit(main())
