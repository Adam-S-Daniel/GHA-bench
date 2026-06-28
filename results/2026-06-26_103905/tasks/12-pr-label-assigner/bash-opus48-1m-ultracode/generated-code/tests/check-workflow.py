#!/usr/bin/env python3
"""Structural validation for .github/workflows/pr-label-assigner.yml.

Parses the workflow YAML and asserts the expected triggers, permissions,
environment, jobs, steps and job dependencies are present, and that every file
the workflow references actually exists on disk.

Usage:
    check-workflow.py <project-dir>

Exits 0 if every check passes, 1 otherwise. Each check prints a PASS/FAIL line.
"""
import os
import sys

import yaml

failures = 0


def check(name, condition):
    global failures
    status = "PASS" if condition else "FAIL"
    if not condition:
        failures += 1
    print(f"[{status}] {name}")


def main():
    if len(sys.argv) != 2:
        print("usage: check-workflow.py <project-dir>", file=sys.stderr)
        return 2
    project = sys.argv[1]
    wf_path = os.path.join(project, ".github", "workflows", "pr-label-assigner.yml")

    check("workflow file exists", os.path.isfile(wf_path))
    if not os.path.isfile(wf_path):
        return 1

    with open(wf_path) as fh:
        wf = yaml.safe_load(fh)

    # YAML 1.1 (PyYAML) parses the bare key `on:` as the boolean True.
    triggers = wf.get("on", wf.get(True))
    check("'on' triggers block exists", triggers is not None)
    # Normalise triggers to a set of event names regardless of YAML shape.
    if isinstance(triggers, dict):
        events = set(triggers.keys())
    elif isinstance(triggers, list):
        events = set(triggers)
    elif isinstance(triggers, str):
        events = {triggers}
    else:
        events = set()
    for ev in ("push", "pull_request", "workflow_dispatch", "schedule"):
        check(f"trigger '{ev}' present", ev in events)
    # schedule must carry a cron entry
    sched_ok = (
        isinstance(triggers, dict)
        and isinstance(triggers.get("schedule"), list)
        and any("cron" in entry for entry in triggers["schedule"])
    )
    check("schedule has a cron expression", sched_ok)

    # Permissions
    perms = wf.get("permissions", {})
    check("permissions.contents defined", "contents" in perms)
    check("permissions.pull-requests defined", "pull-requests" in perms)

    # Workflow-level env
    env = wf.get("env", {})
    check("env.RULES_FILE == config/label-rules.conf",
          env.get("RULES_FILE") == "config/label-rules.conf")

    # Jobs
    jobs = wf.get("jobs", {})
    check("job 'assign-labels' exists", "assign-labels" in jobs)
    check("job 'summary' exists", "summary" in jobs)

    assign = jobs.get("assign-labels", {})
    check("assign-labels runs-on ubuntu-latest",
          assign.get("runs-on") == "ubuntu-latest")

    # Matrix cases
    matrix = assign.get("strategy", {}).get("matrix", {})
    cases = matrix.get("case")
    expected_cases = ["docs", "api", "tests", "mixed", "none", "vendor"]
    check("matrix.case == expected fixture list", cases == expected_cases)

    # Steps: checkout + script invocation
    steps = assign.get("steps", [])
    uses = [s.get("uses", "") for s in steps]
    runs = "\n".join(s.get("run", "") for s in steps)
    check("uses actions/checkout@v4", "actions/checkout@v4" in uses)
    check("a step invokes pr-label-assigner.sh", "pr-label-assigner.sh" in runs)
    check("a step references RULES_FILE", "RULES_FILE" in runs)

    # Job dependency
    needs = jobs.get("summary", {}).get("needs")
    needs_set = {needs} if isinstance(needs, str) else set(needs or [])
    check("summary needs assign-labels", "assign-labels" in needs_set)

    # Referenced files exist on disk
    check("script file exists",
          os.path.isfile(os.path.join(project, "pr-label-assigner.sh")))
    check("rules config exists",
          os.path.isfile(os.path.join(project, "config", "label-rules.conf")))
    for c in expected_cases:
        check(f"fixture '{c}.files' exists",
              os.path.isfile(os.path.join(project, "tests", "fixtures", f"{c}.files")))

    print(f"\n{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
