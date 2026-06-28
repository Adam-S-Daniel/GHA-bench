#!/usr/bin/env python3
"""Normalise a GitHub Actions workflow file to a compact JSON summary.

The bats workflow-structure tests consume this JSON with jq so they can make
structural assertions without re-implementing a YAML parser in bash.

Note the well-known gotcha: PyYAML parses the bare key ``on:`` as the boolean
``True``, so we look it up under both ``"on"`` and ``True``.
"""
import json
import sys

import yaml


def get_on(wf):
    """Return the workflow's trigger section regardless of the on/True quirk."""
    if "on" in wf:
        return wf["on"]
    if True in wf:
        return wf[True]
    return None


def triggers(on_section):
    """Return trigger names as a list (handles str, list and mapping forms)."""
    if on_section is None:
        return []
    if isinstance(on_section, str):
        return [on_section]
    if isinstance(on_section, list):
        return list(on_section)
    if isinstance(on_section, dict):
        return list(on_section.keys())
    return []


def summarise_job(job):
    steps = job.get("steps", []) or []
    return {
        "runs-on": job.get("runs-on"),
        "needs": job.get("needs"),
        "outputs": job.get("outputs", {}) or {},
        "uses": [s.get("uses") for s in steps if isinstance(s, dict) and s.get("uses")],
        "runs": [s.get("run") for s in steps if isinstance(s, dict) and s.get("run")],
    }


def main():
    with open(sys.argv[1], encoding="utf-8") as fh:
        wf = yaml.safe_load(fh)

    on_section = get_on(wf)
    summary = {
        "name": wf.get("name"),
        "triggers": triggers(on_section),
        "on": on_section if isinstance(on_section, dict) else {},
        "permissions": wf.get("permissions"),
        "env": wf.get("env", {}) or {},
        "jobs": {name: summarise_job(job) for name, job in (wf.get("jobs") or {}).items()},
    }
    print(json.dumps(summary, default=str))


if __name__ == "__main__":
    main()
