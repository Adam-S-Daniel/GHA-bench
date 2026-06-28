#!/usr/bin/env python3
"""
Act harness — runs the workflow end-to-end in Docker for several fixture cases.

For each case we:
  1. build a temp git repo containing the project files plus that case's
     fixture data (copied to fixtures/secrets.json, which the workflow reads),
  2. run `act push --rm`, capturing combined stdout/stderr,
  3. append the output to act-result.txt (clearly delimited),
  4. assert act exited 0, every job shows "Job succeeded", and the parsed
     per-urgency counts match the known-good expected values for that input.

Run directly:  python3 tests/run_act_tests.py
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT = os.path.join(HERE, "act-result.txt")

# Files that make up the project (copied into each temp repo).
PROJECT_FILES = [
    "secret_rotation_validator.py",
    ".github/workflows/secret-rotation-validator.yml",
    ".actrc",
]

# Each case: (label, fixture file in fixtures/, expected counts).
CASES = [
    ("mixed-urgency", "secrets.json", {"expired": 1, "warning": 1, "ok": 1}),
    ("all-ok", "secrets_all_ok.json", {"expired": 0, "warning": 0, "ok": 2}),
]


def _copy_into(repo: str):
    for rel in PROJECT_FILES:
        src = os.path.join(HERE, rel)
        dst = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    os.makedirs(os.path.join(repo, "fixtures"), exist_ok=True)


def _run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def run_case(label, fixture, expected, workdir):
    repo = os.path.join(workdir, label)
    os.makedirs(repo, exist_ok=True)
    _copy_into(repo)
    # Stage this case's fixture data as fixtures/secrets.json (workflow input).
    shutil.copy2(
        os.path.join(HERE, "fixtures", fixture),
        os.path.join(repo, "fixtures", "secrets.json"),
    )

    _run(["git", "init", "-q", "-b", "main"], repo)
    _run(["git", "config", "user.email", "t@t.test"], repo)
    _run(["git", "config", "user.name", "test"], repo)
    _run(["git", "add", "-A"], repo)
    _run(["git", "commit", "-q", "-m", "test fixture"], repo)

    # --pull=false: the .actrc maps the runner to a locally-built image; without
    # this act tries to force-pull it and fails with a registry auth error.
    proc = _run(["act", "push", "--rm", "--pull=false"], repo)
    output = proc.stdout + "\n" + proc.stderr

    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 70}\nCASE: {label} (fixture={fixture})\n"
                 f"act exit code: {proc.returncode}\n{'=' * 70}\n")
        fh.write(output)
        fh.write("\n")

    errors = []
    if proc.returncode != 0:
        errors.append(f"act exited {proc.returncode}, expected 0")

    # Every job must succeed (validate + gate).
    succeeded = output.count("Job succeeded")
    if succeeded < 2:
        errors.append(f"expected >=2 'Job succeeded', found {succeeded}")

    # Parse the "Counts -> expired=X warning=Y ok=Z" line from the logs.
    m = re.search(r"Counts -> expired=(\d+) warning=(\d+) ok=(\d+)", output)
    if not m:
        errors.append("could not find 'Counts ->' line in act output")
    else:
        got = {"expired": int(m.group(1)),
               "warning": int(m.group(2)),
               "ok": int(m.group(3))}
        if got != expected:
            errors.append(f"counts {got} != expected {expected}")

    return errors


def main():
    # Fresh result file for this run.
    if os.path.exists(ACT_RESULT):
        os.remove(ACT_RESULT)

    import tempfile
    failures = {}
    with tempfile.TemporaryDirectory() as workdir:
        for label, fixture, expected in CASES:
            print(f"=== Running act case: {label} ===", flush=True)
            errs = run_case(label, fixture, expected, workdir)
            if errs:
                failures[label] = errs
                for e in errs:
                    print(f"  FAIL [{label}]: {e}")
            else:
                print(f"  PASS [{label}]")

    if not os.path.exists(ACT_RESULT):
        print("ERROR: act-result.txt was not created", file=sys.stderr)
        return 1

    if failures:
        print(f"\n{len(failures)} case(s) failed.", file=sys.stderr)
        return 1
    print("\nAll act cases passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
