#!/usr/bin/env python3
"""Workflow structure tests.

Parses the GitHub Actions workflow YAML and asserts on its structure:
triggers, jobs, steps, referenced file paths, and actionlint cleanliness.
Exits non-zero with a clear message on the first failure.
"""
import os
import re
import subprocess
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "semantic-version-bumper.yml")

failures = []


def check(condition, message):
    status = "ok" if condition else "FAIL"
    print(f"[{status}] {message}")
    if not condition:
        failures.append(message)


def main():
    check(os.path.isfile(WORKFLOW), f"workflow file exists: {WORKFLOW}")
    with open(WORKFLOW) as f:
        wf = yaml.safe_load(f)

    # --- triggers ---------------------------------------------------------
    # PyYAML parses the bare key `on` as boolean True.
    triggers = wf.get("on", wf.get(True))
    check(triggers is not None, "workflow declares trigger events")
    check("push" in triggers, "triggers include push")
    check("pull_request" in triggers, "triggers include pull_request")
    check("workflow_dispatch" in triggers, "triggers include workflow_dispatch")
    check(
        triggers.get("push", {}).get("branches") == ["main", "master"],
        "push trigger targets main and master",
    )

    # --- permissions -------------------------------------------------------
    check(wf.get("permissions") == {"contents": "read"}, "permissions are least-privilege (contents: read)")

    # --- jobs ---------------------------------------------------------------
    jobs = wf.get("jobs", {})
    check(set(jobs) == {"test", "bump"}, "workflow defines exactly the jobs: test, bump")
    check(jobs.get("bump", {}).get("needs") == "test", "bump job depends on test job")
    for name, job in jobs.items():
        check(job.get("runs-on") == "ubuntu-latest", f"job '{name}' runs on ubuntu-latest")
        steps = job.get("steps", [])
        check(len(steps) >= 2, f"job '{name}' has at least two steps")
        check(
            steps[0].get("uses", "").startswith("actions/checkout@v4"),
            f"job '{name}' checks out the repo with actions/checkout@v4",
        )

    # --- script references --------------------------------------------------
    run_text = "\n".join(
        step.get("run", "") for job in jobs.values() for step in job.get("steps", [])
    )
    check('node --test "test/*.test.js"' in run_text, "test job runs the unit-test suite")
    check("node src/bumper.js" in run_text, "bump job invokes src/bumper.js")

    # Every path-looking token referenced in run steps must exist in the repo.
    referenced = ["src/bumper.js", "test/bumper.test.js", "fixtures/feat-commits.txt"]
    for rel in referenced:
        # test files are referenced via the "test/*.test.js" glob
        found = rel in run_text or (rel.startswith("test/") and "test/*.test.js" in run_text)
        check(found, f"workflow references {rel}")
        check(os.path.exists(os.path.join(ROOT, rel)), f"referenced path exists on disk: {rel}")

    # --- environment ---------------------------------------------------------
    check(
        jobs.get("bump", {}).get("env", {}).get("RELEASE_DATE") == "2026-07-01",
        "bump job pins RELEASE_DATE for deterministic changelog output",
    )

    # --- actionlint -----------------------------------------------------------
    result = subprocess.run(["actionlint", WORKFLOW], capture_output=True, text=True)
    check(result.returncode == 0, f"actionlint passes (exit code {result.returncode})")
    if result.returncode != 0:
        print(result.stdout + result.stderr)

    if failures:
        print(f"\n{len(failures)} structure check(s) FAILED")
        sys.exit(1)
    print("\nAll workflow structure checks passed.")


if __name__ == "__main__":
    main()
