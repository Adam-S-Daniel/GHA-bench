#!/usr/bin/env bats
#
# Workflow structure tests (static; no act required).
#
# These parse the workflow YAML and assert it has the expected shape: the
# right triggers, jobs, dependency chain and permissions; that it references
# the script + fixtures that actually exist on disk; and that actionlint is
# happy with it.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    WF="${ROOT}/.github/workflows/secret-rotation-validator.yml"
}

# wf_query runs a python snippet with the parsed workflow available as `w`.
# Note the YAML 1.1 gotcha: the `on:` key parses as the boolean True, so the
# trigger block is exposed as both w["on"] and w["triggers"] for convenience.
wf_query() {
    python3 - "$WF" <<PY
import sys, yaml
with open(sys.argv[1]) as fh:
    w = yaml.safe_load(fh)
w["triggers"] = w.get("on", w.get(True))
$1
PY
}

@test "workflow file exists and is valid YAML" {
    [ -f "$WF" ]
    run wf_query 'print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow declares all required triggers" {
    run wf_query '
t = w["triggers"]
for ev in ("push", "pull_request", "schedule", "workflow_dispatch"):
    assert ev in t, ev
print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "schedule trigger has a cron expression" {
    run wf_query 'assert w["triggers"]["schedule"][0]["cron"]; print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow defines lint, test and report jobs" {
    run wf_query '
for j in ("lint", "test", "report"):
    assert j in w["jobs"], j
print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "job dependency chain is lint -> test -> report" {
    run wf_query '
assert w["jobs"]["test"]["needs"] == "lint", w["jobs"]["test"].get("needs")
assert w["jobs"]["report"]["needs"] == "test", w["jobs"]["report"].get("needs")
print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow sets least-privilege read-only permissions" {
    run wf_query 'assert w["permissions"]["contents"] == "read"; print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "every job checks out via actions/checkout@v4" {
    run wf_query '
for name, job in w["jobs"].items():
    uses = [s.get("uses","") for s in job["steps"]]
    assert "actions/checkout@v4" in uses, name
print("ok")'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow references the validator script, which exists on disk" {
    grep -q 'secret-rotation-validator.sh' "$WF"
    [ -f "${ROOT}/secret-rotation-validator.sh" ]
}

@test "workflow references the bats unit test directory, which exists" {
    grep -q 'test/unit/' "$WF"
    [ -d "${ROOT}/test/unit" ]
}

@test "the configured audit fixture exists on disk" {
    run wf_query 'print(w["env"]["CONFIG_FILE"])'
    [ "$status" -eq 0 ]
    [ -f "${ROOT}/${output}" ]
}

@test "actionlint validates the workflow (exit 0)" {
    run actionlint "$WF"
    [ "$status" -eq 0 ]
}
