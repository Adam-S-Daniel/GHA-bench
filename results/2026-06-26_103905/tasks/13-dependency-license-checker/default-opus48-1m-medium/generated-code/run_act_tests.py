#!/usr/bin/env python3
"""
End-to-end test harness: every test case runs THROUGH the GitHub Actions
workflow via `act`, never against the script directly.

For each case we:
  1. Build a temp git repo containing the project files + that case's fixture
     manifest / config / license-db.
  2. Run `act push --rm`, capturing combined output.
  3. Append the output to act-result.txt (clearly delimited).
  4. Assert act exited 0, both jobs report "Job succeeded", and the printed
     report matches the EXACT expected counts / statuses for that fixture.

It also runs workflow-structure tests (YAML shape, script-path references,
actionlint exit code) which need no Docker.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.abspath(__file__))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "dependency-license-checker.yml")
RESULT_FILE = os.path.join(ROOT, "act-result.txt")

# Project files copied into every temp repo (the inputs to the pipeline).
PROJECT_FILES = ["license_checker.py", "license-config.json", "license-db.json"]
PROJECT_DIRS = ["tests", ".github"]


# --------------------------------------------------------------------------
# Test fixtures: each case fully controls the manifest the workflow consumes.
# `expect` holds the EXACT known-good values we assert against the act output.
# --------------------------------------------------------------------------
CASES = [
    {
        "name": "compliant_package_json",
        "manifest": ("package.json", json.dumps({
            "dependencies": {"lodash": "4.17.21", "express": "4.18.2"},
        })),
        "expect": {
            "checker_exit": 0,
            "compliant": True,
            "approved": 2, "denied": 0, "unknown": 0, "total": 2,
        },
    },
    {
        "name": "denied_package_json",
        "manifest": ("package.json", json.dumps({
            "dependencies": {"lodash": "4.17.21", "copyleft-lib": "2.0.0"},
        })),
        "expect": {
            "checker_exit": 1,
            "compliant": False,
            "approved": 1, "denied": 1, "unknown": 0, "total": 2,
        },
    },
    {
        "name": "requirements_with_unknown",
        "manifest": ("requirements.txt",
                     "requests==2.31.0\nflask>=2.0.0\nmystery-pkg==0.1.0\n"),
        "expect": {
            "checker_exit": 1,
            "compliant": False,
            "approved": 2, "denied": 0, "unknown": 1, "total": 3,
        },
    },
]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# --------------------------------------------------------------------------
# Workflow structure tests (no Docker needed).
# --------------------------------------------------------------------------
def structure_tests():
    print("== Workflow structure tests ==")
    with open(WORKFLOW, encoding="utf-8") as fh:
        wf = yaml.safe_load(fh)

    # PyYAML parses the bare `on:` key as the boolean True; accept either form.
    triggers = wf.get("on", wf.get(True))
    assert triggers is not None, "workflow has no triggers"
    for trig in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert trig in triggers, "missing trigger: {}".format(trig)
    print("  triggers OK:", sorted(triggers))

    assert wf["permissions"]["contents"] == "read", "permissions not least-privilege"

    jobs = wf["jobs"]
    assert "unit-tests" in jobs and "license-compliance" in jobs, "missing jobs"
    assert jobs["license-compliance"]["needs"] == "unit-tests", "missing job dependency"
    print("  jobs + needs OK:", sorted(jobs))

    # Every step's referenced script / action must resolve.
    steps = jobs["license-compliance"]["steps"] + jobs["unit-tests"]["steps"]
    blob = json.dumps(steps)
    assert "actions/checkout@v4" in blob, "checkout action not referenced"
    assert "license_checker.py" in blob, "script not referenced by workflow"
    for rel in ("license_checker.py", "license-config.json", "license-db.json"):
        assert os.path.exists(os.path.join(ROOT, rel)), "missing file: {}".format(rel)
    assert os.path.isdir(os.path.join(ROOT, "tests")), "missing tests dir"
    print("  script + path references OK")

    res = run(["actionlint", WORKFLOW])
    assert res.returncode == 0, "actionlint failed:\n{}".format(res.stdout + res.stderr)
    print("  actionlint exit 0 OK")
    print("== structure tests PASSED ==\n")


# --------------------------------------------------------------------------
# act-based end-to-end cases.
# --------------------------------------------------------------------------
def setup_repo(case):
    """Create a temp git repo with project files + this case's fixture."""
    repo = tempfile.mkdtemp(prefix="lic-act-")
    for f in PROJECT_FILES:
        shutil.copy(os.path.join(ROOT, f), os.path.join(repo, f))
    for d in PROJECT_DIRS:
        shutil.copytree(os.path.join(ROOT, d), os.path.join(repo, d))
    # Copy the .actrc so act uses the same pre-built image.
    if os.path.exists(os.path.join(ROOT, ".actrc")):
        shutil.copy(os.path.join(ROOT, ".actrc"), os.path.join(repo, ".actrc"))

    fname, content = case["manifest"]
    with open(os.path.join(repo, fname), "w", encoding="utf-8") as fh:
        fh.write(content)

    for c in (["git", "init", "-q"],
              ["git", "add", "-A"],
              ["git", "-c", "user.email=t@t", "-c", "user.name=t",
               "commit", "-q", "-m", "fixture"]):
        r = run(c, cwd=repo)
        assert r.returncode == 0, "git setup failed: {}\n{}".format(c, r.stderr)
    return repo


def _strip_act_prefix(line):
    """act prints '[Workflow/Job]  | <content>'; return just <content>."""
    if "|" in line:
        return re.sub(r"^.*?\|\s?", "", line)
    return line


def parse_report(output):
    """Pull the printed license-report.json object out of the act log."""
    lines = [_strip_act_prefix(l) for l in output.splitlines()]
    # Find the marker, then accumulate lines until the JSON braces balance.
    start = None
    for i, l in enumerate(lines):
        if "license-report.json" in l and "-----" in l:
            start = i + 1
            break
    if start is None:
        return None
    buf, started = [], False
    for l in lines[start:]:
        if not started:
            if l.strip() != "{":
                continue
            started = True
        buf.append(l)
        # json.dump(indent=2) puts the top-level closing brace at column 0;
        # all nested closes are indented, so a bare "}" ends the object.
        if started and l.rstrip() == "}":
            break
    try:
        return json.loads("\n".join(buf))
    except json.JSONDecodeError:
        return None


def assert_case(case, output, exit_code):
    exp = case["expect"]
    failures = []

    if exit_code != 0:
        failures.append("act exit code {} != 0".format(exit_code))

    succeeded = output.count("Job succeeded")
    if succeeded < 2:
        failures.append("expected 2 'Job succeeded', found {}".format(succeeded))

    m = re.search(r"CHECKER_EXIT=(\d+)", output)
    if not m:
        failures.append("CHECKER_EXIT not found in output")
    elif int(m.group(1)) != exp["checker_exit"]:
        failures.append("CHECKER_EXIT={} != expected {}".format(
            m.group(1), exp["checker_exit"]))

    report = parse_report(output)
    if report is None:
        failures.append("could not parse license-report.json from output")
    else:
        if report["compliant"] != exp["compliant"]:
            failures.append("compliant={} != {}".format(
                report["compliant"], exp["compliant"]))
        for k in ("approved", "denied", "unknown", "total"):
            got = report["summary"][k]
            if got != exp[k]:
                failures.append("summary.{}={} != {}".format(k, got, exp[k]))
    return failures


def run_act_case(case, result_fh):
    print("== act case: {} ==".format(case["name"]))
    repo = setup_repo(case)
    try:
        # --pull=false: the act image is built locally and must not be pulled.
        proc = run(["act", "push", "--rm", "--pull=false"], cwd=repo)
        output = proc.stdout + "\n" + proc.stderr
        result_fh.write("\n" + "=" * 70 + "\n")
        result_fh.write("TEST CASE: {}\n".format(case["name"]))
        result_fh.write("act exit code: {}\n".format(proc.returncode))
        result_fh.write("=" * 70 + "\n")
        result_fh.write(output)
        result_fh.flush()

        failures = assert_case(case, output, proc.returncode)
        if failures:
            print("  FAILED:")
            for f in failures:
                print("    -", f)
            return False
        print("  PASSED (exit 0, jobs succeeded, exact values matched)")
        return True
    finally:
        shutil.rmtree(repo, ignore_errors=True)


def main():
    structure_tests()
    ok = True
    with open(RESULT_FILE, "w", encoding="utf-8") as result_fh:
        result_fh.write("act results for dependency-license-checker workflow\n")
        for case in CASES:
            if not run_act_case(case, result_fh):
                ok = False
    print("\n== {} ==".format("ALL E2E CASES PASSED" if ok else "SOME CASES FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
