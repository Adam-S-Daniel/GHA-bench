#!/usr/bin/env python3
"""Static structure check for the semantic-version-bumper workflow YAML.

Used by the bats "structure" tests instead of asserting on raw text, so the
check survives formatting changes. Exits 0 and prints nothing when every
expected trigger/job/step is present; otherwise prints each failure and
exits 1.
"""
import sys

import yaml


def fail(errors, message):
    errors.append(message)


def main():
    if len(sys.argv) != 2:
        print("usage: check_workflow_structure.py <workflow.yml>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)

    errors = []

    # YAML 1.1 parses the bare key `on` as the boolean True; accept either
    # spelling so this check doesn't depend on the loader's quirks.
    triggers = doc.get("on", doc.get(True))
    if triggers is None:
        fail(errors, "missing top-level 'on' triggers")
        triggers = {}
    for expected in ("push", "workflow_dispatch"):
        if expected not in triggers:
            fail(errors, f"expected trigger '{expected}' not found in 'on'")

    jobs = doc.get("jobs", {})
    for expected_job in ("bump-version", "report-release"):
        if expected_job not in jobs:
            fail(errors, f"expected job '{expected_job}' not found")

    bump_job = jobs.get("bump-version", {})
    if bump_job.get("runs-on") != "ubuntu-latest":
        fail(errors, "bump-version job does not run on ubuntu-latest")

    steps = bump_job.get("steps", [])
    uses = [s.get("uses") for s in steps if isinstance(s, dict)]
    if not any(isinstance(u, str) and u.startswith("actions/checkout@") for u in uses):
        fail(errors, "bump-version job does not use actions/checkout")

    runs = [s.get("run", "") for s in steps if isinstance(s, dict)]
    if not any("bump_version.sh" in r for r in runs):
        fail(errors, "bump-version job does not invoke bump_version.sh")

    report_job = jobs.get("report-release", {})
    needs = report_job.get("needs")
    if needs != "bump-version" and needs != ["bump-version"]:
        fail(errors, "report-release job does not declare 'needs: bump-version'")

    if errors:
        for e in errors:
            print(f"STRUCTURE ERROR: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
