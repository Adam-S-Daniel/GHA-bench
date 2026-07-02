#!/usr/bin/env python3
"""Structure checks for dependency-license-checker.yml.

Not the implementation language for this task (that's Bash) -- this is a
small test *helper* used only by the workflow-structure bats tests, because
bash has no built-in YAML parser. Each subcommand prints "OK: <detail>" and
exits 0 on success, or "FAIL: <reason>" and exits 1 on failure, so bats can
assert on both exit code and message.

Usage: check_workflow.py <triggers|jobs|steps|paths> <workflow.yml> <project_root>
"""
import sys
from pathlib import Path

import yaml


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def ok(msg):
    print(f"OK: {msg}")
    sys.exit(0)


def load(workflow_path):
    with open(workflow_path) as f:
        return yaml.safe_load(f)


def check_triggers(doc, _root):
    # PyYAML parses the bare `on:` key as boolean True in YAML 1.1.
    triggers = doc.get("on", doc.get(True))
    if triggers is None:
        fail("no 'on:' trigger block found")
    required = {"push", "pull_request", "schedule", "workflow_dispatch"}
    missing = required - set(triggers.keys())
    if missing:
        fail(f"missing triggers: {sorted(missing)}")
    if not triggers.get("schedule"):
        fail("schedule trigger has no cron entries")
    ok(f"all required triggers present: {sorted(required)}")


def check_jobs(doc, _root):
    jobs = doc.get("jobs", {})
    for name in ("lint-and-test", "license-check"):
        if name not in jobs:
            fail(f"missing job: {name}")
    needs = jobs["license-check"].get("needs")
    needs = [needs] if isinstance(needs, str) else (needs or [])
    if "lint-and-test" not in needs:
        fail("license-check must declare 'needs: lint-and-test'")
    perms = doc.get("permissions")
    if not perms or perms.get("contents") != "read":
        fail("top-level permissions must set contents: read")
    ok("jobs declared with correct dependency and least-privilege permissions")


def check_steps(doc, _root):
    jobs = doc.get("jobs", {})
    all_steps = [s for job in jobs.values() for s in job.get("steps", [])]

    uses = [s.get("uses", "") for s in all_steps]
    if not any(u.startswith("actions/checkout@v4") for u in uses):
        fail("no step uses actions/checkout@v4")

    runs = " ".join(s.get("run", "") for s in all_steps)
    for needle in ("bats", "shellcheck", "license-checker.sh"):
        if needle not in runs:
            fail(f"no run: step references '{needle}'")
    ok("steps use checkout@v4 and invoke bats/shellcheck/license-checker.sh")


def check_paths(doc, root):
    jobs = doc.get("jobs", {})
    all_steps = [s for job in jobs.values() for s in job.get("steps", [])]
    referenced = set()
    for s in all_steps:
        run = s.get("run", "")
        for candidate in (
            "license-checker.sh",
            "tests/license-checker.bats",
        ):
            if candidate in run:
                referenced.add(candidate)
    # env-block references (manifest/config/db paths).
    for val in doc.get("env", {}).values():
        if isinstance(val, str) and "/" in val:
            referenced.add(val)

    if not referenced:
        fail("no file paths found referenced in the workflow")

    missing = [p for p in referenced if not (root / p).exists()]
    if missing:
        fail(f"referenced paths do not exist: {sorted(missing)}")
    ok(f"all referenced paths exist: {sorted(referenced)}")


COMMANDS = {
    "triggers": check_triggers,
    "jobs": check_jobs,
    "steps": check_steps,
    "paths": check_paths,
}


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in COMMANDS:
        print(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}> <workflow.yml> <project_root>")
        sys.exit(2)
    _, cmd, workflow_path, root = sys.argv
    doc = load(workflow_path)
    COMMANDS[cmd](doc, Path(root))


if __name__ == "__main__":
    main()
