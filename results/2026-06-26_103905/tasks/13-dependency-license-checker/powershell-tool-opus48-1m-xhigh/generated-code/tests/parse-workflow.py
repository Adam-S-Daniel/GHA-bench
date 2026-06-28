#!/usr/bin/env python3
"""Parse a GitHub Actions workflow YAML file and emit a normalized JSON summary
used by the PowerShell workflow-structure tests.

Note: PyYAML follows YAML 1.1, which parses the bare key ``on`` as the boolean
``True``. We therefore look the triggers up under both 'on' and True.
"""
import json
import sys

import yaml


def steps_of(jobs, job_name):
    job = jobs.get(job_name, {}) or {}
    return [
        {"name": s.get("name"), "uses": s.get("uses"), "run": s.get("run")}
        for s in (job.get("steps") or [])
    ]


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)

    on = doc.get("on", doc.get(True))
    jobs = doc.get("jobs", {}) or {}
    license_check = jobs.get("license-check", {}) or {}
    strategy = license_check.get("strategy", {}) or {}
    matrix = strategy.get("matrix", {}) or {}

    out = {
        "name": doc.get("name"),
        "triggers": sorted(on.keys()) if isinstance(on, dict) else [str(on)],
        "permissions": doc.get("permissions"),
        "env": doc.get("env"),
        "jobs": sorted(jobs.keys()),
        "license_check_needs": license_check.get("needs"),
        "matrix_include": matrix.get("include"),
        "unit_test_steps": steps_of(jobs, "unit-tests"),
        "license_check_steps": steps_of(jobs, "license-check"),
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
