#!/usr/bin/env bash
# Test harness that drives the artifact-cleanup-script GitHub Actions workflow
# through `act`, once per test-case scenario. For each case it materializes a
# throwaway git repo containing this project's files (with that case's
# fixture-selecting env default patched into the workflow), runs
# `act push --rm`, and asserts on exact expected output.
#
# All assertions here run against the real pipeline output. This is
# intentional: the task requires every test case to execute through the
# GitHub Actions workflow via act, not the script directly.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
FILES_TO_COPY=(src tests package.json bun.lock tsconfig.json .actrc .gitignore .github)

: > "$RESULT_FILE"

FAILURES=0

log_section() {
  {
    echo "===================================================================="
    echo "TEST CASE: $1"
    echo "===================================================================="
  } >> "$RESULT_FILE"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS [$label]: found \"$needle\""
  else
    echo "  FAIL [$label]: expected output to contain: $needle"
    FAILURES=$((FAILURES + 1))
  fi
}

# Runs one test case: copies the project into a fresh temp git repo, applies
# an optional sed mutation to the workflow file, runs act, appends output to
# act-result.txt, and leaves the result in $LAST_OUTPUT / $LAST_EXIT.
run_case() {
  local case_name="$1"
  local mutation="${2:-}"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  echo "==> [$case_name] temp repo: $tmp_dir"

  for f in "${FILES_TO_COPY[@]}"; do
    cp -R "$PROJECT_ROOT/$f" "$tmp_dir/"
  done

  if [[ -n "$mutation" ]]; then
    eval "$mutation" "$tmp_dir/.github/workflows/artifact-cleanup-script.yml"
  fi

  (
    cd "$tmp_dir"
    git init -q
    git config user.email "act-test-harness@example.com"
    git config user.name "Act Test Harness"
    git add -A
    git commit -q -m "test case: $case_name"
  )

  log_section "$case_name"

  set +e
  LAST_OUTPUT="$(cd "$tmp_dir" && act push --rm 2>&1)"
  LAST_EXIT=$?
  set -e

  {
    echo "$LAST_OUTPUT"
    echo ""
    echo "act exit code: $LAST_EXIT"
  } >> "$RESULT_FILE"

  rm -rf "$tmp_dir"
}

assert_exit_zero() {
  local label="$1"
  if [[ "$LAST_EXIT" -eq 0 ]]; then
    echo "  PASS [$label]: act exited 0"
  else
    echo "  FAIL [$label]: act exited $LAST_EXIT"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_job_succeeded_count() {
  local label="$1" expected="$2"
  local count
  count=$(grep -o "Job succeeded" <<< "$LAST_OUTPUT" | wc -l | tr -d ' ')
  if [[ "$count" -eq "$expected" ]]; then
    echo "  PASS [$label]: $count/$expected jobs reported 'Job succeeded'"
  else
    echo "  FAIL [$label]: expected $expected 'Job succeeded' lines, got $count"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "## Test case 1: baseline fixture, dry run (workflow defaults)"
run_case "baseline-dry-run"
assert_exit_zero "baseline-dry-run exit code"
assert_job_succeeded_count "baseline-dry-run jobs" 2
assert_contains "$LAST_OUTPUT" "Mode: DRY RUN (no artifacts deleted)" "baseline-dry-run mode"
assert_contains "$LAST_OUTPUT" "Total artifacts: 12" "baseline-dry-run total artifacts"
assert_contains "$LAST_OUTPUT" "Retained: 4" "baseline-dry-run retained count"
assert_contains "$LAST_OUTPUT" "Deleted: 8" "baseline-dry-run deleted count"
assert_contains "$LAST_OUTPUT" "Reclaimed: 376421216 bytes" "baseline-dry-run reclaimed bytes"
assert_contains "$LAST_OUTPUT" "Deleted by reason: max-age=4, keep-latest-n=3, max-total-size=1" "baseline-dry-run reasons"

echo "## Test case 2: baseline fixture, live run (DRY_RUN default patched to false)"
run_case "baseline-live-run" "sed -i \"s/dry_run || 'true'/dry_run || 'false'/\""
assert_exit_zero "baseline-live-run exit code"
assert_job_succeeded_count "baseline-live-run jobs" 2
assert_contains "$LAST_OUTPUT" "Mode: LIVE (artifacts were deleted)" "baseline-live-run mode"
assert_contains "$LAST_OUTPUT" "Total artifacts: 12" "baseline-live-run total artifacts"
assert_contains "$LAST_OUTPUT" "Retained: 4" "baseline-live-run retained count"
assert_contains "$LAST_OUTPUT" "Deleted: 8" "baseline-live-run deleted count"
assert_contains "$LAST_OUTPUT" "Reclaimed: 376421216 bytes" "baseline-live-run reclaimed bytes"
assert_contains "$LAST_OUTPUT" "Deleting artifact ci-build-101 (build-output)..." "baseline-live-run deletion log"

echo "## Test case 3: empty-workload fixture, dry run (MOCK_DATA_FIXTURE default patched)"
run_case "empty-workload-dry-run" "sed -i \"s/mock_data_fixture || 'baseline'/mock_data_fixture || 'empty-workload'/\""
assert_exit_zero "empty-workload-dry-run exit code"
assert_job_succeeded_count "empty-workload-dry-run jobs" 2
assert_contains "$LAST_OUTPUT" "Mode: DRY RUN (no artifacts deleted)" "empty-workload-dry-run mode"
assert_contains "$LAST_OUTPUT" "Total artifacts: 3" "empty-workload-dry-run total artifacts"
assert_contains "$LAST_OUTPUT" "Retained: 3" "empty-workload-dry-run retained count"
assert_contains "$LAST_OUTPUT" "Deleted: 0" "empty-workload-dry-run deleted count"
assert_contains "$LAST_OUTPUT" "Reclaimed: 0 bytes" "empty-workload-dry-run reclaimed bytes"

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All act-driven test cases passed. See $RESULT_FILE for full output." | tee -a "$RESULT_FILE"
else
  echo "$FAILURES assertion(s) failed. See $RESULT_FILE for full output." | tee -a "$RESULT_FILE"
  exit 1
fi
