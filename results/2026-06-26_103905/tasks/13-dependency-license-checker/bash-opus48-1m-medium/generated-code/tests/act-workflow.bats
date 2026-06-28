#!/usr/bin/env bats
#
# Workflow tests. These exercise the GitHub Actions workflow itself:
#   1. Static structure checks on the YAML (triggers, jobs, steps, paths).
#   2. actionlint validation.
#   3. End-to-end execution of the workflow through `act` for three fixture
#      cases, asserting on EXACT expected report values.
#
# Every functional test case runs through the pipeline via `act` (not the
# script directly). The combined act output is saved to act-result.txt in the
# project root, one clearly-delimited block per case.

setup_file() {
  PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PROJECT_DIR
  WORKFLOW="$PROJECT_DIR/.github/workflows/dependency-license-checker.yml"
  export WORKFLOW
  ACT_RESULT="$PROJECT_DIR/act-result.txt"
  export ACT_RESULT

  # Only the act cases are expensive; skip them unless act + docker exist.
  if ! command -v act >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
    export ACT_AVAILABLE=0
    return 0
  fi
  export ACT_AVAILABLE=1

  # Fresh report artifact for this run.
  : > "$ACT_RESULT"

  # Run all three cases once (3 act invocations total) and cache each case's
  # combined log + exit code for the per-case assertions below.
  _run_act_case "A_approved" "package.json" '{ "dependencies": { "left-pad": "1.3.0", "lodash": "^4.17.21" } }'
  _run_act_case "B_denied"   "package.json" '{ "dependencies": { "left-pad": "1.3.0", "evil-pkg": "2.0.0" } }'
  _run_act_case "C_unknown"  "requirements.txt" $'requests==2.31.0\nmystery==1.0.0\n'
}

# _run_act_case <case_id> <manifest_filename> <manifest_contents>
# Builds an isolated git repo containing the project files plus exactly this
# case's manifest, runs `act push --rm`, and records the result.
_run_act_case() {
  local case_id="$1" manifest_name="$2" manifest_body="$3"
  local work; work="$(mktemp -d)"

  # Copy the project files needed by the workflow.
  cp "$PROJECT_DIR/license-checker.sh" "$work/"
  cp -r "$PROJECT_DIR/config" "$work/"
  cp -r "$PROJECT_DIR/.github" "$work/"
  cp "$PROJECT_DIR/.actrc" "$work/" 2>/dev/null || true

  # Provide exactly one manifest so the workflow auto-detects this case's input.
  mkdir -p "$work/fixtures"
  printf '%s' "$manifest_body" > "$work/fixtures/$manifest_name"

  # act needs a git repo to evaluate the push event.
  (
    cd "$work"
    git init -q
    git config user.email ci@example.com
    git config user.name CI
    git add -A
    git commit -qm "case $case_id"
  )

  local log="$BATS_FILE_TMPDIR/$case_id.log"
  local code
  # Capture act's exit code without letting setup_file's errexit abort on a
  # non-zero result, so every case is recorded for diagnosis.
  if ( cd "$work" && act push --rm ) >"$log" 2>&1; then
    code=0
  else
    code=$?
  fi
  echo "$code" > "$BATS_FILE_TMPDIR/$case_id.code"

  # Append delimited output to the required artifact.
  {
    echo "==================== ACT CASE: $case_id ===================="
    echo "manifest: fixtures/$manifest_name"
    echo "exit code: $code"
    echo "-----------------------------------------------------------"
    cat "$log"
    echo
  } >> "$ACT_RESULT"

  rm -rf "$work"
}

# Convenience: load a cached case log into $output / $status-style vars.
_load_case() {
  local id="$1"
  if [[ "${ACT_AVAILABLE:-0}" -ne 1 ]]; then
    skip "act or docker not available"
  fi
  CASE_LOG="$(cat "$BATS_FILE_TMPDIR/$id.log")"
  CASE_CODE="$(cat "$BATS_FILE_TMPDIR/$id.code")"
}

# ---------------- Static structure tests (fast) --------------------------

@test "workflow: referenced script and config paths exist" {
  PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  [ -f "$PROJECT_DIR/license-checker.sh" ]
  [ -f "$PROJECT_DIR/config/allow-list.txt" ]
  [ -f "$PROJECT_DIR/config/deny-list.txt" ]
  [ -f "$PROJECT_DIR/config/licenses.db" ]
}

@test "workflow: declares push, pull_request, schedule and workflow_dispatch triggers" {
  WF="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.github/workflows/dependency-license-checker.yml"
  grep -qE '^  push:' "$WF"
  grep -qE '^  pull_request:' "$WF"
  grep -qE '^  schedule:' "$WF"
  grep -qE '^  workflow_dispatch:' "$WF"
}

@test "workflow: defines permissions and the license-check job" {
  WF="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.github/workflows/dependency-license-checker.yml"
  grep -qE '^permissions:' "$WF"
  grep -qE 'contents: read' "$WF"
  grep -qE '^  license-check:' "$WF"
}

@test "workflow: checks out the repo and invokes license-checker.sh" {
  WF="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.github/workflows/dependency-license-checker.yml"
  grep -qE 'actions/checkout@v4' "$WF"
  grep -qE 'license-checker\.sh' "$WF"
}

@test "workflow: passes actionlint cleanly" {
  WF="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.github/workflows/dependency-license-checker.yml"
  if ! command -v actionlint >/dev/null 2>&1; then skip "actionlint not installed"; fi
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

# ---------------- act execution tests (one per case) ---------------------

@test "act case A: clean package.json -> all APPROVED, RESULT PASS, job succeeded" {
  _load_case "A_approved"
  [ "$CASE_CODE" -eq 0 ]
  [[ "$CASE_LOG" == *"left-pad@1.3.0 MIT APPROVED"* ]]
  [[ "$CASE_LOG" == *"lodash@4.17.21 MIT APPROVED"* ]]
  [[ "$CASE_LOG" == *"RESULT: PASS"* ]]
  [[ "$CASE_LOG" == *"Job succeeded"* ]]
}

@test "act case B: denied license -> DENIED line, RESULT FAIL, job still succeeded" {
  _load_case "B_denied"
  [ "$CASE_CODE" -eq 0 ]
  [[ "$CASE_LOG" == *"left-pad@1.3.0 MIT APPROVED"* ]]
  [[ "$CASE_LOG" == *"evil-pkg@2.0.0 GPL-3.0 DENIED"* ]]
  [[ "$CASE_LOG" == *"RESULT: FAIL"* ]]
  [[ "$CASE_LOG" == *"Job succeeded"* ]]
}

@test "act case C: requirements.txt -> APPROVED + UNKNOWN, job succeeded" {
  _load_case "C_unknown"
  [ "$CASE_CODE" -eq 0 ]
  [[ "$CASE_LOG" == *"requests@2.31.0 Apache-2.0 APPROVED"* ]]
  [[ "$CASE_LOG" == *"mystery@1.0.0 UNKNOWN UNKNOWN"* ]]
  [[ "$CASE_LOG" == *"Job succeeded"* ]]
}

@test "act: act-result.txt artifact exists and contains all three cases" {
  if [[ "${ACT_AVAILABLE:-0}" -ne 1 ]]; then skip "act or docker not available"; fi
  [ -f "$ACT_RESULT" ]
  grep -q "ACT CASE: A_approved" "$ACT_RESULT"
  grep -q "ACT CASE: B_denied" "$ACT_RESULT"
  grep -q "ACT CASE: C_unknown" "$ACT_RESULT"
}
