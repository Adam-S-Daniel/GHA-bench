#!/usr/bin/env python3
"""Structural validator for the Semantic Version Bumper workflow.

Usage: wf_check.py <workflow.yml> <check>
  check in: triggers | jobs | steps | references

Exits 0 and prints "OK" when the requested check passes; otherwise prints the
problems and exits 1. Used by the bats workflow-structure tests.
"""
import os
import sys

import yaml


def load(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def get_on(doc):
    # YAML 1.1 (PyYAML) parses the bare key `on:` as the boolean True, so the
    # triggers may live under either "on" or True.
    if "on" in doc:
        return doc["on"]
    return doc.get(True, {})


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def main():
    if len(sys.argv) != 3:
        print("usage: wf_check.py <workflow.yml> <check>", file=sys.stderr)
        return 2

    wf_path, check = sys.argv[1], sys.argv[2]
    doc = load(wf_path)
    on = get_on(doc)
    jobs = doc.get("jobs", {}) or {}
    errors = []

    if check == "triggers":
        for trig in ("push", "pull_request", "workflow_dispatch", "schedule"):
            if trig not in on:
                errors.append(f"missing trigger: {trig}")

    elif check == "jobs":
        for job in ("version-bump", "summary"):
            if job not in jobs:
                errors.append(f"missing job: {job}")
        needs = as_list(jobs.get("summary", {}).get("needs"))
        if "version-bump" not in needs:
            errors.append("job 'summary' must declare needs: version-bump")
        # permissions should be present (and read-only is appropriate here)
        if "permissions" not in doc:
            errors.append("workflow should declare top-level permissions")

    elif check == "steps":
        vb = jobs.get("version-bump", {})
        steps = vb.get("steps", []) or []
        uses = [s.get("uses", "") for s in steps]
        if not any(u.startswith("actions/checkout@") for u in uses):
            errors.append("version-bump must use actions/checkout")
        runs = "\n".join(s.get("run", "") or "" for s in steps)
        if "semver-bump.sh" not in runs:
            errors.append("version-bump must run semver-bump.sh")
        summ = jobs.get("summary", {})
        if not (summ.get("steps")):
            errors.append("summary must have at least one step")

    elif check == "references":
        # wf_path is <root>/.github/workflows/<file>.yml -> go up three levels.
        base = os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.abspath(wf_path)))
        )
        if not os.path.isfile(os.path.join(base, "semver-bump.sh")):
            errors.append("referenced script semver-bump.sh not found on disk")
        if not os.path.isdir(os.path.join(base, "fixtures")):
            errors.append("referenced fixtures/ directory not found on disk")

    else:
        print(f"unknown check: {check}", file=sys.stderr)
        return 2

    if errors:
        for err in errors:
            print(err)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
