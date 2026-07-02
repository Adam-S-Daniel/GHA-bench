#!/usr/bin/env python3
"""Structure tests for .github/workflows/semantic-version-bumper.yml.

Parses the workflow YAML and asserts on its shape (triggers, jobs, steps,
permissions, dependencies), verifies that every file the workflow references
actually exists in the repo, and asserts that actionlint exits 0.

Run: python3 test/workflow_structure_test.py
"""
import os
import subprocess
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "semantic-version-bumper.yml")

failures = []


def check(name, condition, detail=""):
    status = "ok" if condition else "FAIL"
    print(f"[{status}] {name}" + (f" - {detail}" if detail and not condition else ""))
    if not condition:
        failures.append(name)


with open(WORKFLOW, encoding="utf-8") as fh:
    wf = yaml.safe_load(fh)

# --- Triggers ---------------------------------------------------------------
# PyYAML (YAML 1.1) parses the bare key `on:` as boolean True.
triggers = wf.get("on", wf.get(True))
check("workflow parses as a mapping", isinstance(wf, dict))
check("has trigger section", isinstance(triggers, dict), f"got: {triggers!r}")
for event in ("push", "pull_request", "workflow_dispatch"):
    check(f"trigger includes {event}", event in triggers)

# --- Permissions ------------------------------------------------------------
check("permissions are least-privilege (contents: read)",
      wf.get("permissions") == {"contents": "read"}, f"got: {wf.get('permissions')!r}")

# --- Jobs -------------------------------------------------------------------
jobs = wf.get("jobs", {})
check("has unit-tests job", "unit-tests" in jobs)
check("has version-bump job", "version-bump" in jobs)
check("version-bump depends on unit-tests",
      jobs.get("version-bump", {}).get("needs") == "unit-tests")
for job_id, job in jobs.items():
    check(f"{job_id} runs on ubuntu-latest", job.get("runs-on") == "ubuntu-latest")
    steps = job.get("steps", [])
    check(f"{job_id} has steps", len(steps) > 0)
    check(f"{job_id} checks out the repo first",
          steps and steps[0].get("uses", "").startswith("actions/checkout@v4"),
          f"first step: {steps[0] if steps else None!r}")

# --- Script references ------------------------------------------------------
def job_script(job_id):
    return "\n".join(s.get("run", "") for s in jobs.get(job_id, {}).get("steps", []))

check("unit-tests job runs the node:test suite",
      "node --test test/semver-bump.test.js" in job_script("unit-tests"))
check("version-bump job invokes src/semver-bump.js",
      "node src/semver-bump.js" in job_script("version-bump"))

# Every path the workflow references must exist in the repo.
for rel in ("src/semver-bump.js", "test/semver-bump.test.js",
            "fixtures/commits-feat.log", "VERSION"):
    check(f"referenced path exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))

# --- actionlint -------------------------------------------------------------
proc = subprocess.run(["actionlint", WORKFLOW], capture_output=True, text=True)
check("actionlint exits 0", proc.returncode == 0, proc.stdout + proc.stderr)

print()
if failures:
    print(f"FAILED: {len(failures)} structure check(s): {failures}")
    sys.exit(1)
print("All workflow structure checks passed.")
