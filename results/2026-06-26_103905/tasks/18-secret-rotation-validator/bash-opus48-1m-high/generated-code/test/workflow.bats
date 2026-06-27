#!/usr/bin/env bats
#
# Workflow tests for .github/workflows/secret-rotation-validator.yml
#
# Two groups of tests:
#   1. Static structure tests — parse the YAML, verify triggers/jobs/steps,
#      confirm referenced script + fixture paths exist, and that actionlint
#      passes. These are fast and have no external dependencies.
#   2. act integration assertions — assert on the output captured by
#      test/run-act-cases.sh (which runs the workflow end-to-end via act for
#      each fixture). Run that harness first:
#
#        bash test/run-act-cases.sh
#
#      Those tests fail with a clear message if the harness has not been run.

setup() {
  TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  PROJECT_ROOT="$( cd "$TEST_DIR/.." >/dev/null 2>&1 && pwd )"
  WORKFLOW="$PROJECT_ROOT/.github/workflows/secret-rotation-validator.yml"
  ACT_RESULT="$PROJECT_ROOT/act-result.txt"
  OUT_DIR="$PROJECT_ROOT/test/.act-out"
}

# Read the value at a dotted YAML/JSON path via python (pyyaml).
yq_path() {
  python3 - "$WORKFLOW" "$1" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
cur = doc
for part in sys.argv[2].split('.'):
    if part == '':
        continue
    if isinstance(cur, list):
        cur = cur[int(part)]
    else:
        cur = cur[part]
print(cur)
PY
}

# --------------------------------------------------------------------------
# Static structure tests
# --------------------------------------------------------------------------

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow is valid YAML" {
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "actionlint passes with exit code 0" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares all expected triggers" {
  # PyYAML parses the bare `on:` key as boolean True, so inspect the raw keys.
  run python3 - "$WORKFLOW" <<'PY'
import yaml, sys
doc = yaml.safe_load(open(sys.argv[1]))
# The trigger mapping is under the key True (YAML 1.1 folds `on` -> True) or 'on'.
trig = doc.get(True, doc.get('on'))
for t in ('push', 'pull_request', 'schedule', 'workflow_dispatch'):
    assert t in trig, f"missing trigger: {t}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "workflow defines the validate and summarize jobs" {
  run yq_path "jobs.validate.name"
  [ "$status" -eq 0 ]
  run yq_path "jobs.summarize.name"
  [ "$status" -eq 0 ]
}

@test "summarize job depends on validate job" {
  run yq_path "jobs.summarize.needs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate"* ]]
}

@test "workflow sets least-privilege contents:read permission" {
  run yq_path "permissions.contents"
  [ "$status" -eq 0 ]
  [ "$output" = "read" ]
}

@test "workflow references the validator script that exists on disk" {
  # The script path used in the run steps must exist in the repo.
  grep -q "secret-rotation-validator.sh" "$WORKFLOW"
  [ -f "$PROJECT_ROOT/secret-rotation-validator.sh" ]
}

@test "workflow's CONFIG_FILE fixture exists on disk" {
  run yq_path "env.CONFIG_FILE"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_ROOT/$output" ]
}

@test "workflow uses actions/checkout@v4" {
  grep -q "actions/checkout@v4" "$WORKFLOW"
}

@test "all case fixtures referenced by the harness exist" {
  [ -f "$PROJECT_ROOT/fixtures/secrets.json" ]
  [ -f "$PROJECT_ROOT/fixtures/cases/all-ok.json" ]
  [ -f "$PROJECT_ROOT/fixtures/cases/all-expired.json" ]
}

# --------------------------------------------------------------------------
# act integration assertions (require: bash test/run-act-cases.sh)
# --------------------------------------------------------------------------

require_act_run() {
  if [ ! -f "$ACT_RESULT" ] || [ ! -d "$OUT_DIR" ]; then
    skip "act harness not run yet; run: bash test/run-act-cases.sh"
  fi
}

@test "act-result.txt artifact exists and is non-empty" {
  require_act_run
  [ -s "$ACT_RESULT" ]
}

@test "act-result.txt records exit_code 0 for every case" {
  require_act_run
  # Every recorded case block must report exit_code: 0.
  run grep -c "^exit_code: 0$" "$ACT_RESULT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
  # And there must be no non-zero exit codes.
  ! grep -qE "^exit_code: [^0]" "$ACT_RESULT"
}

@test "act mixed case: both jobs succeed" {
  require_act_run
  [ -f "$OUT_DIR/mixed.txt" ]
  # validate + summarize => two "Job succeeded" lines.
  run grep -c "Job succeeded" "$OUT_DIR/mixed.txt"
  [ "$output" -eq 2 ]
}

@test "act mixed case: exact summary 1 expired / 1 warning / 1 ok / 3 total" {
  require_act_run
  grep -q "SUMMARY expired=1 warning=1 ok=1 total=3" "$OUT_DIR/mixed.txt"
  grep -q "RESULT expired=1 warning=1 ok=1 total=3" "$OUT_DIR/mixed.txt"
}

@test "act all-ok case: both jobs succeed" {
  require_act_run
  [ -f "$OUT_DIR/all-ok.txt" ]
  run grep -c "Job succeeded" "$OUT_DIR/all-ok.txt"
  [ "$output" -eq 2 ]
}

@test "act all-ok case: exact summary 0 expired / 0 warning / 2 ok / 2 total" {
  require_act_run
  grep -q "SUMMARY expired=0 warning=0 ok=2 total=2" "$OUT_DIR/all-ok.txt"
  grep -q "RESULT expired=0 warning=0 ok=2 total=2" "$OUT_DIR/all-ok.txt"
}

@test "act all-expired case: both jobs succeed" {
  require_act_run
  [ -f "$OUT_DIR/all-expired.txt" ]
  run grep -c "Job succeeded" "$OUT_DIR/all-expired.txt"
  [ "$output" -eq 2 ]
}

@test "act all-expired case: exact summary 2 expired / 0 warning / 0 ok / 2 total" {
  require_act_run
  grep -q "SUMMARY expired=2 warning=0 ok=0 total=2" "$OUT_DIR/all-expired.txt"
  grep -q "RESULT expired=2 warning=0 ok=0 total=2" "$OUT_DIR/all-expired.txt"
}

@test "act all-expired case: warning annotation is emitted" {
  require_act_run
  grep -q "secret(s) require immediate rotation" "$OUT_DIR/all-expired.txt"
}
