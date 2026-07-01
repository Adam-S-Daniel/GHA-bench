#!/usr/bin/env bash
# Test harness that drives the GitHub Actions workflow through `act`.
#
# Sets up an isolated temp git repo containing the project files (aggregator.py,
# tests/, fixtures/, .github/), runs `act push --rm` against it, captures the
# output to act-result.txt, and asserts:
#   - act exited 0
#   - every job printed "Job succeeded" (unit-tests, both matrix legs, summary)
#   - the aggregated Markdown contains the EXACT expected totals for each of
#     the two fixture combinations the workflow exercises in this single run:
#       1. the matrix legs (ubuntu-latest passing/skipped, macos-latest with one
#          real failure) -> proves totals + flaky-test detection
#       2. the "clean" all-pass sanity fixtures -> proves the all-green path
#          and that "no flaky tests" is reported when nothing is flaky
#
# Only ONE `act push` invocation is used (well under the 3-run budget) since
# both fixture combinations are already exercised within this single workflow run.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="${PROJECT_DIR}/act-result.txt"
: > "$RESULT_FILE"

FAIL=0

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERTION FAILED: $desc"
    echo "  expected to find: $needle"
    FAIL=1
  else
    echo "ASSERTION OK: $desc"
  fi
}

tmp_repo="$(mktemp -d)"
cleanup() { rm -rf "$tmp_repo"; }
trap cleanup EXIT

rsync -a \
  --exclude '.git' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude 'act-result.txt' \
  "$PROJECT_DIR"/ "$tmp_repo"/

(
  cd "$tmp_repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test Harness"
  git add -A
  git commit -q -m "test-results-aggregator: act test run"
)

echo "##### BEGIN TEST CASE: default-fixtures (matrix legs + all-pass sanity) #####" >> "$RESULT_FILE"

artifact_server_dir="$(mktemp -d)"
output="$(cd "$tmp_repo" && act push --rm --pull=false --artifact-server-path "$artifact_server_dir" 2>&1)"
rm -rf "$artifact_server_dir"
act_exit=$?

echo "$output" >> "$RESULT_FILE"
echo "##### act exit code: $act_exit #####" >> "$RESULT_FILE"
echo "##### END TEST CASE #####" >> "$RESULT_FILE"

echo "--- act exit code: $act_exit ---"
if [[ "$act_exit" -ne 0 ]]; then
  echo "ASSERTION FAILED: act exited $act_exit (expected 0)"
  FAIL=1
else
  echo "ASSERTION OK: act exited 0"
fi

job_success_count="$(grep -c 'Job succeeded' <<<"$output")"
# 4 job runs: unit-tests, aggregate-matrix-results x2 (ubuntu + macos legs), aggregate-summary
if [[ "$job_success_count" -lt 4 ]]; then
  echo "ASSERTION FAILED: expected 4 'Job succeeded' lines (one per job run), got $job_success_count"
  FAIL=1
else
  echo "ASSERTION OK: found $job_success_count 'Job succeeded' lines (>=4 job runs)"
fi

# Matrix legs (ubuntu-latest: 2 passed/1 skipped, macos-latest: 2 passed/1 failed):
# totals passed=4 failed=1 skipped=1 total=6, with test_flaky_network_call flagged flaky.
assert_contains "$output" "| 4 ✅ | 1 ❌ | 1 ⏭️ | 6 | " "matrix totals: passed=4 failed=1 skipped=1 total=6"
assert_contains "$output" "## Flaky Tests" "Flaky Tests section present"
assert_contains "$output" "test_flaky_network_call" "flaky test test_flaky_network_call is reported"

# All-pass sanity fixtures (junit_all_pass.xml + results_all_pass.json):
# totals passed=4 failed=0 skipped=0 total=4, no flaky tests.
assert_contains "$output" "| 4 ✅ | 0 ❌ | 0 ⏭️ | 4 | " "sanity totals: passed=4 failed=0 skipped=0 total=4"
assert_contains "$output" "No flaky tests detected" "no flaky tests reported for the clean sanity run"

echo ""
if [[ "$FAIL" -ne 0 ]]; then
  echo "ONE OR MORE ASSERTIONS FAILED"
  exit 1
fi
echo "ALL ASSERTIONS PASSED"
exit 0
