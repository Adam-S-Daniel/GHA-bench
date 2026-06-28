#!/usr/bin/env python3
"""Structural validation of the workflow YAML.

Parses the workflow file and asserts it has the expected triggers, jobs, job
dependencies, permissions, and that the build job consumes the generated matrix.
Prints STRUCTURE_OK on success; raises (non-zero exit) on any failure.

Note: PyYAML parses the bare key ``on:`` as the boolean ``True`` (YAML 1.1),
so we look it up under both ``'on'`` and ``True``.
"""
import sys
import yaml


def main(path: str) -> int:
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)

    assert isinstance(doc, dict), "workflow must be a mapping"
    assert doc.get("name"), "workflow must have a name"

    # --- triggers -----------------------------------------------------------
    on = doc.get("on", doc.get(True))
    assert on is not None, "workflow has no 'on' triggers"
    triggers = set(on.keys()) if isinstance(on, dict) else set(on)
    for trig in ("push", "pull_request", "workflow_dispatch", "schedule"):
        assert trig in triggers, f"missing trigger: {trig}"
    # schedule must define a cron entry
    sched = on["schedule"] if isinstance(on, dict) else None
    assert sched and "cron" in sched[0], "schedule trigger needs a cron entry"

    # --- permissions (least privilege) --------------------------------------
    perms = doc.get("permissions", {})
    assert perms.get("contents") == "read", "permissions.contents must be 'read'"

    # --- jobs ---------------------------------------------------------------
    jobs = doc.get("jobs", {})
    assert "validate" in jobs, "missing 'validate' job"
    assert "build" in jobs, "missing 'build' job"

    # --- job dependency -----------------------------------------------------
    needs = jobs["build"].get("needs")
    needs = [needs] if isinstance(needs, str) else (needs or [])
    assert "validate" in needs, "build job must 'needs: validate'"

    # --- validate job references the scripts --------------------------------
    validate_text = yaml.safe_dump(jobs["validate"])
    assert "run-fixtures.sh" in validate_text, "validate job must run run-fixtures.sh"
    assert "matrix-generator.sh" in validate_text, "validate job must use matrix-generator.sh"
    assert "actions/checkout@v4" in validate_text, "validate job must checkout the repo"

    # --- validate job exposes outputs ---------------------------------------
    outputs = jobs["validate"].get("outputs", {})
    assert "matrix" in outputs, "validate job must output 'matrix'"

    # --- build job consumes the generated matrix ----------------------------
    matrix_expr = str(jobs["build"]["strategy"]["matrix"])
    assert "fromJson" in matrix_expr, "build matrix must use fromJson(...)"
    assert "validate" in matrix_expr and "outputs.matrix" in matrix_expr, \
        "build matrix must reference needs.validate.outputs.matrix"

    print("STRUCTURE_OK")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: check_structure.py <workflow.yml>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
