#!/usr/bin/env bash
# =============================================================================
# run-act-tests.sh — end-to-end test harness that runs EVERY test case through
# the GitHub Actions workflow via `act` (nektos/act).
#
# For each test case it:
#   1. Sets up a temp git repo containing the project files + that case's
#      fixture selection (via the RESULTS_DIR repository variable)
#   2. Runs `act push --rm`, appending the full output to act-result.txt
#   3. Asserts act exited 0
#   4. Asserts on EXACT expected values in the aggregated markdown output
#   5. Asserts every job reports "Job succeeded" and no bats test failed
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACT_RESULT="$PROJECT_ROOT/act-result.txt"
ACT_IMAGE="act-ubuntu-pwsh:latest"
FAILURES=0

: > "$ACT_RESULT"

# run_case <name> <results-dir-var> <expected-string>...
run_case() {
  local name="$1" results_dir="$2"
  shift 2
  local expected=("$@")

  echo "=== Running act test case: $name (RESULTS_DIR=$results_dir) ==="

  local tmp
  tmp="$(mktemp -d)"
  # 1. Temp git repo with project files + fixtures
  cp -r "$PROJECT_ROOT/aggregate-test-results.sh" \
        "$PROJECT_ROOT/test" \
        "$PROJECT_ROOT/fixtures" \
        "$PROJECT_ROOT/fixtures-allpass" \
        "$PROJECT_ROOT/.github" \
        "$tmp/"
  git -C "$tmp" init -q
  git -C "$tmp" add -A
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci commit -qm "test case: $name"

  # 2. Run the workflow through act, capturing all output
  local out="$tmp/act-output.txt" rc
  (cd "$tmp" && act push --rm --pull=false \
      -P "ubuntu-latest=$ACT_IMAGE" \
      --var "RESULTS_DIR=$results_dir") > "$out" 2>&1
  rc=$?

  {
    echo "==================================================================="
    echo "=== ACT TEST CASE: $name (RESULTS_DIR=$results_dir, exit=$rc) ==="
    echo "==================================================================="
    cat "$out"
    echo "=== END ACT TEST CASE: $name ==="
    echo
  } >> "$ACT_RESULT"

  # 3. act must exit 0
  if [ "$rc" -ne 0 ]; then
    echo "FAIL [$name]: act exited with code $rc (see act-result.txt)"
    FAILURES=$((FAILURES + 1))
    rm -rf "$tmp"
    return
  fi
  echo "PASS [$name]: act exited 0"

  # 4. Exact expected values in the workflow output
  local e
  for e in "${expected[@]}"; do
    if grep -qF -- "$e" "$out"; then
      echo "PASS [$name]: output contains expected value: $e"
    else
      echo "FAIL [$name]: output MISSING expected value: $e"
      FAILURES=$((FAILURES + 1))
    fi
  done

  # 5a. Both jobs (test, aggregate) must report success
  local succeeded
  succeeded="$(grep -c 'Job succeeded' "$out")"
  if [ "$succeeded" -ge 2 ]; then
    echo "PASS [$name]: all $succeeded jobs reported 'Job succeeded'"
  else
    echo "FAIL [$name]: expected 2 'Job succeeded' lines, found $succeeded"
    FAILURES=$((FAILURES + 1))
  fi

  # 5b. No bats test may have failed inside the workflow
  if grep -q 'not ok' "$out"; then
    echo "FAIL [$name]: bats reported failing tests inside the workflow"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [$name]: no failing bats tests in workflow output"
  fi

  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Test case 1: mixed fixtures (default) — known-good aggregate values:
#   11 tests total, 7 passed, 3 failed, 1 skipped, 8.60s,
#   one flaky test (suite.test_flaky), one consistent failure (suite.test_beta)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # literal backticks: expected markdown code spans
run_case "mixed-results-with-flaky" "fixtures" \
  "| Total | 11 |" \
  "| Passed | 7 |" \
  "| Failed | 3 |" \
  "| Skipped | 1 |" \
  "| Duration | 8.60s |" \
  '`suite.test_flaky` — passed 2, failed 1' \
  '`suite.test_beta` — failed 2 time(s)' \
  "ok 26 actionlint passes on the workflow (exit code 0)" \
  "AGGREGATION_OK=true"

# ---------------------------------------------------------------------------
# Test case 2: all-passing fixtures — 3 tests, no failures, no flaky tests
# ---------------------------------------------------------------------------
run_case "all-passing-no-flaky" "fixtures-allpass" \
  "| Total | 3 |" \
  "| Passed | 3 |" \
  "| Failed | 0 |" \
  "| Skipped | 0 |" \
  "| Duration | 1.00s |" \
  "No flaky tests detected" \
  "No consistently failing tests" \
  "AGGREGATION_OK=true"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "=== ALL ACT TEST CASES PASSED (output in act-result.txt) ==="
  exit 0
else
  echo "=== $FAILURES ASSERTION(S) FAILED (see act-result.txt) ==="
  exit 1
fi
