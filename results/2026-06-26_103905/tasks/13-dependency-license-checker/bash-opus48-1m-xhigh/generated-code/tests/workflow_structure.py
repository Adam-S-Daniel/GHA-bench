#!/usr/bin/env python3
"""Tiny structural query tool for the GitHub Actions workflow.

Usage: workflow_structure.py <workflow.yml> <check>

It loads the workflow YAML and prints a normalised answer for the requested
check, so the bats workflow-structure tests can assert on exact values without
re-implementing a YAML parser in bash. Exits non-zero on a missing key so a
broken structure surfaces as a test failure.

Note the classic GitHub Actions gotcha: PyYAML parses the bare key `on:` as the
boolean True, so the trigger block must be looked up under True *or* 'on'.
"""
import sys
import yaml


def triggers(d):
    on = d.get(True, d.get("on"))
    if isinstance(on, dict):
        keys = list(on.keys())
    elif isinstance(on, list):
        keys = list(on)
    else:
        keys = [on]
    return ",".join(sorted(str(k) for k in keys))


def main():
    if len(sys.argv) != 3:
        print("usage: workflow_structure.py <file> <check>", file=sys.stderr)
        return 2
    path, check = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as fh:
        d = yaml.safe_load(fh)

    jobs = d.get("jobs", {})

    if check == "triggers":
        print(triggers(d))
    elif check == "jobs":
        print(",".join(sorted(jobs.keys())))
    elif check == "summary-needs":
        print(jobs["summary"]["needs"])
    elif check == "checkout-ref":
        for step in jobs["license-check"]["steps"]:
            if str(step.get("uses", "")).startswith("actions/checkout"):
                print(step["uses"])
                return 0
        print("MISSING", file=sys.stderr)
        return 1
    elif check == "runs-on":
        print(jobs["license-check"]["runs-on"])
    elif check == "permissions":
        print(d.get("permissions", {}).get("contents", "MISSING"))
    elif check == "env-keys":
        print(",".join(sorted(d.get("env", {}).keys())))
    elif check == "references-script":
        blob = yaml.safe_dump(d)
        print("yes" if "license-checker.sh" in blob else "no")
    elif check == "steps-license-check":
        print(",".join(s.get("name", "?") for s in jobs["license-check"]["steps"]))
    else:
        print(f"unknown check: {check}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
