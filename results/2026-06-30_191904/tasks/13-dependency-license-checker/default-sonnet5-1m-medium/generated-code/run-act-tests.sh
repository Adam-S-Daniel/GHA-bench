#!/usr/bin/env bash
# Runs the dependency-license-checker workflow through `act` for each fixture
# test case, capturing output to act-result.txt and asserting exact expected
# values in that output (not just "something ran").
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
: > "$RESULT_FILE"

OVERALL_STATUS=0

# name | fixture-source-dir (relative to fixtures/) | expected substrings (newline separated)
run_case() {
  local case_name="$1"
  local fixture_src="$2"
  shift 2
  local expected=("$@")

  echo "=== Test case: $case_name ===" | tee -a "$RESULT_FILE"

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  # Copy the whole project (script + workflow + fixtures) into an isolated
  # temp git repo, per the task's isolation requirement.
  cp -r "$PROJECT_DIR"/. "$workdir"/
  rm -rf "$workdir/.git" "$workdir/act-result.txt" "$workdir/__pycache__" "$workdir/.pytest_cache"

  # Overlay this test case's fixture data over the default fixtures.
  if [ -d "$PROJECT_DIR/fixtures/$fixture_src" ]; then
    cp "$PROJECT_DIR/fixtures/$fixture_src/package.json" "$workdir/fixtures/package.json"
    cp "$PROJECT_DIR/fixtures/$fixture_src/license-config.json" "$workdir/fixtures/license-config.json"
    cp "$PROJECT_DIR/fixtures/$fixture_src/license-data.json" "$workdir/fixtures/license-data.json"
  fi

  (
    cd "$workdir" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Runner"
    git add -A
    git commit -q -m "test case: $case_name"
  )

  local act_output
  act_output="$(cd "$workdir" && act push --rm --pull=false 2>&1)"
  local act_exit=$?

  {
    echo "--- act exit code: $act_exit ---"
    echo "$act_output"
    echo "=== End test case: $case_name ==="
    echo
  } >> "$RESULT_FILE"

  local case_status=0
  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with $act_exit (expected 0)" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  if ! grep -q "Job succeeded" <<<"$act_output"; then
    echo "FAIL [$case_name]: expected 'Job succeeded' in act output" | tee -a "$RESULT_FILE"
    case_status=1
  fi

  for expected_str in "${expected[@]}"; do
    if ! grep -qF "$expected_str" <<<"$act_output"; then
      echo "FAIL [$case_name]: expected output to contain: $expected_str" | tee -a "$RESULT_FILE"
      case_status=1
    fi
  done

  if [ "$case_status" -eq 0 ]; then
    echo "PASS [$case_name]" | tee -a "$RESULT_FILE"
  else
    OVERALL_STATUS=1
  fi
}

run_case "mixed-licenses" "." \
  "left-pad@1.3.0: MIT -> APPROVED" \
  "restrictive-lib@2.0.0: GPL-3.0 -> DENIED" \
  "mystery-lib@0.1.0: UNKNOWN -> UNKNOWN" \
  "Approved: 1" \
  "Denied: 1" \
  "Unknown: 1" \
  '"approved": 1' \
  '"denied": 1' \
  '"unknown": 1'

run_case "all-clean" "case-clean" \
  "left-pad@1.3.0: MIT -> APPROVED" \
  "express@4.18.2: MIT -> APPROVED" \
  "Approved: 2" \
  "Denied: 0" \
  "Unknown: 0"

echo "=== Summary ===" | tee -a "$RESULT_FILE"
if [ "$OVERALL_STATUS" -eq 0 ]; then
  echo "ALL TEST CASES PASSED" | tee -a "$RESULT_FILE"
else
  echo "ONE OR MORE TEST CASES FAILED" | tee -a "$RESULT_FILE"
fi

exit "$OVERALL_STATUS"
