#!/usr/bin/env python3
"""Parse a GitHub Actions workflow YAML file into a JSON summary so bats
tests can assert on its structure with jq, without embedding PyYAML calls
in every test case. Handles the classic "on:" YAML 1.1 boolean gotcha
(PyYAML parses an unquoted `on` key as the boolean True)."""
import sys
import json
import yaml


def main() -> int:
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f)

    triggers = doc.get("on", doc.get(True))
    if isinstance(triggers, str):
        triggers = [triggers]
    elif isinstance(triggers, dict):
        triggers = list(triggers.keys())
    elif not isinstance(triggers, list):
        triggers = []

    jobs = doc.get("jobs", {}) or {}
    job_details = {}
    for name, job in jobs.items():
        steps = job.get("steps", []) or []
        job_details[name] = {
            "runs-on": job.get("runs-on"),
            "needs": job.get("needs"),
            "uses": [s["uses"] for s in steps if "uses" in s],
            "run_snippets": [s["run"] for s in steps if "run" in s],
        }

    out = {
        "triggers": triggers,
        "jobs": list(jobs.keys()),
        "job_details": job_details,
        "permissions": doc.get("permissions", {}),
        "env": doc.get("env", {}),
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
