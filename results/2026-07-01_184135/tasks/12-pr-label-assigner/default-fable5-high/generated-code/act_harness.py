"""End-to-end test harness: run every labeler test case through the
GitHub Actions workflow via `act` (nektos/act).

For each case it builds a temp git repo containing the project files plus
that case's fixture data (the mocked PR changed-file list and the rules
config), runs `act push --rm`, appends the output to act-result.txt, and
asserts:
  * act exited 0
  * the output contains the EXACT expected 'LABELS: ...' line
  * the output contains the exact 'FINAL LABEL SET: ...' echoed from the
    step output (proves data flowed through GITHUB_OUTPUT)
  * both workflow jobs report 'Job succeeded'
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
RESULT_FILE = os.path.join(ROOT, "act-result.txt")

# Files the temp repo needs to run the workflow. tests/test_workflow.py is
# host-only (needs actionlint), so it is deliberately not copied.
PROJECT_FILES = [
    "labeler.py",
    "tests/__init__.py",
    "tests/test_labeler.py",
    ".github/workflows/pr-label-assigner.yml",
    ".actrc",  # maps ubuntu-latest to the local runner image
]

DEFAULT_RULES = {
    "rules": [
        {"pattern": "docs/**", "labels": ["documentation"]},
        {"pattern": "src/api/**", "labels": ["api", "backend"]},
        {"pattern": "src/**", "labels": ["source"]},
        {"pattern": "*.test.*", "labels": ["tests"]},
        {"pattern": ".github/**", "labels": ["ci"]},
    ]
}

PRIORITY_RULES = {
    "rules": [
        {"pattern": "src/**", "labels": ["source"]},
        {"pattern": "src/generated/**", "labels": ["generated", "skip-review"], "priority": 5},
        {"pattern": "docs/**", "labels": ["documentation"]},
    ]
}

CASES = [
    {
        "name": "case1-mixed-changes",
        "rules": DEFAULT_RULES,
        "changed_files": [
            "docs/getting-started.md",
            "src/api/users.py",
            "src/core/engine.py",
            "webapp/app.test.js",
        ],
        # docs -> documentation; src/api -> api,backend (+source via src/**);
        # src/core -> source; *.test.* -> tests
        "expected": "api,backend,documentation,source,tests",
    },
    {
        "name": "case2-priority-conflict",
        "rules": PRIORITY_RULES,
        "changed_files": ["src/generated/schema_pb2.py", "src/main.py"],
        # schema_pb2.py matches src/** (prio 0) AND src/generated/** (prio 5):
        # the high-priority rule suppresses 'source' for that file. main.py
        # still gets 'source' — priority is resolved per file.
        "expected": "generated,skip-review,source",
    },
    {
        "name": "case3-no-matching-rules",
        "rules": DEFAULT_RULES,
        "changed_files": ["LICENSE", "Makefile"],
        "expected": "(none)",
    },
]

JOB_NAMES = ["unit-tests", "assign-labels"]


def build_repo(case, repo):
    """Assemble a temp git repo: project files + this case's fixtures."""
    for rel in PROJECT_FILES:
        dst = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(dst) or repo, exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), dst)
    os.makedirs(os.path.join(repo, "fixtures"), exist_ok=True)
    with open(os.path.join(repo, "fixtures", "rules.json"), "w") as fh:
        json.dump(case["rules"], fh, indent=2)
    with open(os.path.join(repo, "fixtures", "changed_files.txt"), "w") as fh:
        fh.write("\n".join(case["changed_files"]) + "\n")
    git_env = {**os.environ,
               "GIT_AUTHOR_NAME": "harness", "GIT_AUTHOR_EMAIL": "h@test",
               "GIT_COMMITTER_NAME": "harness", "GIT_COMMITTER_EMAIL": "h@test"}
    for cmd in (["git", "init", "-q", "-b", "main"],
                ["git", "add", "-A"],
                ["git", "commit", "-qm", f"fixture: {case['name']}"]):
        subprocess.run(cmd, cwd=repo, env=git_env, check=True,
                       capture_output=True)


def run_case(case, log):
    repo = tempfile.mkdtemp(prefix=f"labeler-{case['name']}-")
    failures = []
    try:
        build_repo(case, repo)
        proc = subprocess.run(
            ["act", "push", "--rm", "--pull=false"],
            cwd=repo, capture_output=True, text=True, timeout=420,
        )
        output = proc.stdout + proc.stderr
        log.write(f"\n{'=' * 72}\n=== TEST CASE: {case['name']}\n"
                  f"=== changed files: {case['changed_files']}\n"
                  f"=== expected label set: {case['expected']}\n"
                  f"=== act exit code: {proc.returncode}\n{'=' * 72}\n")
        log.write(output)

        if proc.returncode != 0:
            failures.append(f"act exited {proc.returncode}, expected 0")
        expected_line = f"LABELS: {case['expected']}"
        if expected_line not in output:
            failures.append(f"missing exact output {expected_line!r}")
        final_line = f"FINAL LABEL SET: {case['expected']}"
        if final_line not in output:
            failures.append(f"missing exact output {final_line!r}")
        for job in JOB_NAMES:
            if not any(job in line and "Job succeeded" in line
                       for line in output.splitlines()):
                failures.append(f"job {job!r} did not report 'Job succeeded'")
    finally:
        shutil.rmtree(repo, ignore_errors=True)
    return failures


def main():
    # Pre-flight on the host: actionlint + workflow structure tests + the
    # full TDD unit suite (the same unit suite also runs inside act).
    for desc, cmd in [
        ("actionlint", ["actionlint", ".github/workflows/pr-label-assigner.yml"]),
        ("workflow structure tests", [sys.executable, "-m", "unittest", "tests.test_workflow", "-v"]),
        ("unit test suite", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."]),
    ]:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        status = "PASS" if proc.returncode == 0 else "FAIL"
        print(f"[pre-flight] {desc}: {status}")
        if proc.returncode != 0:
            print(proc.stdout + proc.stderr)
            return 1

    all_failures = {}
    with open(RESULT_FILE, "w") as log:
        log.write("act end-to-end results for pr-label-assigner\n")
        for case in CASES:
            print(f"[act] running {case['name']} ...", flush=True)
            failures = run_case(case, log)
            verdict = "PASS" if not failures else "FAIL: " + "; ".join(failures)
            log.write(f"\n>>> CASE VERDICT [{case['name']}]: {verdict}\n")
            print(f"[act] {case['name']}: {verdict}")
            if failures:
                all_failures[case["name"]] = failures
        log.write(f"\n{'=' * 72}\nOVERALL: "
                  f"{'ALL CASES PASSED' if not all_failures else 'FAILURES: ' + repr(all_failures)}\n")

    if all_failures:
        print(f"FAILED: {all_failures}")
        return 1
    print(f"All {len(CASES)} act test cases passed. Results in {RESULT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
