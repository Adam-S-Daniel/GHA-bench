#!/usr/bin/env bats
# Project & workflow structure tests.
#
# These are fast (no Docker) and assert the *shape* of the deliverables:
# the script exists and is lintable, the sample fixtures exist, and the
# GitHub Actions workflow has the required triggers / permissions / steps and
# passes actionlint. They are written first (red) and drive the implementation.

load 'test_helper'

@test "aggregator script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "script passes bash -n syntax check" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script passes shellcheck" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sample JUnit XML and JSON fixtures exist" {
  run bash -c 'ls "$PROJECT_ROOT"/fixtures/*.xml'
  [ "$status" -eq 0 ]
  run bash -c 'ls "$PROJECT_ROOT"/fixtures/*.json'
  [ "$status" -eq 0 ]
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow passes actionlint cleanly (exit 0)" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request, workflow_dispatch and schedule triggers" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
# PyYAML parses the bare key `on:` as the boolean True (YAML 1.1).
on = wf.get("on", wf.get(True))
assert isinstance(on, dict), f"expected a mapping of triggers, got {type(on)}"
for trigger in ("push", "pull_request", "workflow_dispatch", "schedule"):
    assert trigger in on, f"missing trigger: {trigger}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "workflow declares least-privilege permissions (contents: read)" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
perms = wf.get("permissions")
assert perms is not None, "no permissions block declared"
assert perms.get("contents") == "read", f"expected contents: read, got {perms!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "workflow references the aggregator script by its real path" {
  run grep -q 'aggregate-test-results.sh' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -f "$SCRIPT" ]
}

@test "workflow checks out the repo and runs the aggregator script" {
  run python3 - "$WORKFLOW" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf.get("jobs") or {}
assert jobs, "no jobs defined"
ok_checkout = ok_run = False
for job in jobs.values():
    for step in job.get("steps", []):
        if str(step.get("uses", "")).startswith("actions/checkout@"):
            ok_checkout = True
        if "aggregate-test-results.sh" in str(step.get("run", "")):
            ok_run = True
assert ok_checkout, "no actions/checkout step found"
assert ok_run, "no run step invokes aggregate-test-results.sh"
print("ok")
PY
  [ "$status" -eq 0 ]
}
