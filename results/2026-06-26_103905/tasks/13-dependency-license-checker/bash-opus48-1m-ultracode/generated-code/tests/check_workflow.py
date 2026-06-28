#!/usr/bin/env python3
"""Structural validator for the dependency-license-checker workflow.

Parses the workflow YAML and asserts the structure the rest of the pipeline
relies on. Each subcommand exits 0 on success and 1 on failure, printing a
short human-readable explanation either way so failures are diagnosable from
bats output.

Usage:
    check_workflow.py <triggers|jobs|steps|paths> <workflow.yml> [project_root]
"""
import os
import sys

import yaml


def load(path):
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def get_on(workflow):
    # YAML 1.1 parses the bare key `on` as the boolean True, so accept both.
    if "on" in workflow:
        return workflow["on"]
    return workflow.get(True)


def fail(msg):
    print("FAIL: " + msg)
    return 1


def ok(msg):
    print("OK: " + msg)
    return 0


def check_triggers(workflow, _root):
    on = get_on(workflow)
    if not isinstance(on, dict):
        return fail(f"`on` is not a mapping of triggers: {on!r}")
    required = {"push", "pull_request", "schedule", "workflow_dispatch"}
    missing = required - set(on.keys())
    if missing:
        return fail(f"missing triggers: {sorted(missing)} (have {sorted(on.keys())})")
    # schedule must carry a cron entry.
    sched = on.get("schedule")
    if not (isinstance(sched, list) and sched and "cron" in sched[0]):
        return fail(f"schedule trigger lacks a cron entry: {sched!r}")
    return ok(f"triggers present: {sorted(on.keys())}; cron={sched[0]['cron']!r}")


def check_jobs(workflow, _root):
    jobs = workflow.get("jobs", {})
    for job in ("lint-and-test", "license-check"):
        if job not in jobs:
            return fail(f"missing job: {job} (have {sorted(jobs.keys())})")
    needs = jobs["license-check"].get("needs")
    needs = [needs] if isinstance(needs, str) else (needs or [])
    if "lint-and-test" not in needs:
        return fail(f"license-check does not depend on lint-and-test (needs={needs})")
    perms = workflow.get("permissions", {})
    if not (isinstance(perms, dict) and perms.get("contents") == "read"):
        return fail(f"permissions are not least-privilege contents:read (got {perms!r})")
    return ok("jobs lint-and-test + license-check present; dependency + permissions correct")


def _all_steps(job):
    return job.get("steps", []) or []


def check_steps(workflow, _root):
    jobs = workflow.get("jobs", {})
    lint_steps = _all_steps(jobs.get("lint-and-test", {}))
    check_steps_ = _all_steps(jobs.get("license-check", {}))

    def uses_checkout(steps):
        return any(str(s.get("uses", "")).startswith("actions/checkout@v4") for s in steps)

    if not uses_checkout(lint_steps):
        return fail("lint-and-test does not use actions/checkout@v4")
    if not uses_checkout(check_steps_):
        return fail("license-check does not use actions/checkout@v4")

    lint_run = "\n".join(s.get("run", "") for s in lint_steps)
    if "bats" not in lint_run:
        return fail("lint-and-test never runs bats")
    if "shellcheck" not in lint_run:
        return fail("lint-and-test never runs shellcheck")

    check_run = "\n".join(s.get("run", "") for s in check_steps_)
    if "license-checker.sh" not in check_run:
        return fail("license-check never invokes license-checker.sh")
    return ok("checkout@v4 + bats + shellcheck + license-checker.sh invocation all present")


def check_paths(workflow, root):
    env = workflow.get("env", {}) or {}
    referenced = ["license-checker.sh"]
    for key in ("POLICY_FILE", "LICENSE_DB"):
        if key in env:
            referenced.append(env[key])
    missing = [p for p in referenced if not os.path.isfile(os.path.join(root, p))]
    if missing:
        return fail(f"workflow references files that do not exist: {missing}")
    # At least one default manifest must exist for an out-of-the-box run.
    manifests = ["fixtures/package.json", "fixtures/requirements.txt"]
    if not any(os.path.isfile(os.path.join(root, m)) for m in manifests):
        return fail(f"no default manifest found ({manifests})")
    return ok(f"all referenced files exist: {referenced} (+ a default manifest)")


CHECKS = {
    "triggers": check_triggers,
    "jobs": check_jobs,
    "steps": check_steps,
    "paths": check_paths,
}


def main(argv):
    if len(argv) < 3 or argv[1] not in CHECKS:
        print(f"usage: {argv[0]} <{'|'.join(CHECKS)}> <workflow.yml> [root]")
        return 2
    workflow = load(argv[2])
    root = argv[3] if len(argv) > 3 else "."
    return CHECKS[argv[1]](workflow, root)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
