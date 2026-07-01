#!/usr/bin/env bash
# Test harness that drives every test case through the real GitHub Actions
# workflow via `act`, rather than invoking the PowerShell tool directly.
#
# For each case: build an isolated temp git repo containing the project
# files plus that case's changed-files fixture (swapped in as
# fixtures/changed-files.json, the path the workflow reads by default),
# run `act push --rm`, and assert against exact expected values.
#
# All act output is appended to act-result.txt (recreated at the top of
# each run) with a clear per-case delimiter.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
OVERALL_STATUS=0

: > "$RESULT_FILE"

# case name | fixture file | expected "Final Labels:" value
CASES=(
  "case1-docs-only|fixtures/changed-files-case1.json|documentation"
  "case2-mixed-api-and-tests|fixtures/changed-files-case2.json|api, documentation, tests"
  "case3-exclusive-priority-conflict|fixtures/changed-files-case3.json|api, source"
)

run_case() {
  local case_name="$1" fixture_rel="$2" expected_labels="$3"
  local tmp_repo
  tmp_repo="$(mktemp -d)"

  echo "=== Test case: $case_name ==="

  # Copy project files (excluding VCS metadata and prior results) into an
  # isolated temp git repo, then swap in this case's fixture as the
  # workflow's default changed-files input.
  rsync -a \
    --exclude '.git' \
    --exclude 'act-result.txt' \
    --exclude 'run-act-tests.sh' \
    "$PROJECT_DIR/" "$tmp_repo/"

  cp "$PROJECT_DIR/$fixture_rel" "$tmp_repo/fixtures/changed-files.json"

  (
    cd "$tmp_repo" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "act-test-harness"
    git add -A
    git commit -q -m "test case: $case_name"
    act push --rm --pull=false
  ) > "$tmp_repo/act-output.txt" 2>&1
  local act_exit=$?

  {
    echo "===== TEST CASE: $case_name ====="
    echo "Fixture: $fixture_rel"
    echo "Expected Final Labels: $expected_labels"
    echo "--- act output ---"
    cat "$tmp_repo/act-output.txt"
    echo "--- act exit code: $act_exit ---"
    echo
  } >> "$RESULT_FILE"

  local case_status=0

  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with code $act_exit (expected 0)"
    case_status=1
  fi

  local job_ok_count
  job_ok_count=$(grep -c 'Job succeeded' "$tmp_repo/act-output.txt")
  if [ "$job_ok_count" -lt 2 ]; then
    echo "FAIL [$case_name]: expected 2 'Job succeeded' lines (test + assign-labels), found $job_ok_count"
    case_status=1
  fi

  if ! grep -qF "Final Labels: $expected_labels" "$tmp_repo/act-output.txt"; then
    echo "FAIL [$case_name]: expected exact line 'Final Labels: $expected_labels' not found in act output"
    case_status=1
  fi

  if [ "$case_status" -eq 0 ]; then
    echo "PASS [$case_name]: act succeeded, both jobs succeeded, labels == '$expected_labels'"
  fi

  rm -rf "$tmp_repo"
  return $case_status
}

for entry in "${CASES[@]}"; do
  IFS='|' read -r name fixture expected <<< "$entry"
  if ! run_case "$name" "$fixture" "$expected"; then
    OVERALL_STATUS=1
  fi
done

echo
if [ "$OVERALL_STATUS" -eq 0 ]; then
  echo "All act-driven test cases PASSED. See $RESULT_FILE for full output."
else
  echo "One or more act-driven test cases FAILED. See $RESULT_FILE for full output."
fi

exit $OVERALL_STATUS
