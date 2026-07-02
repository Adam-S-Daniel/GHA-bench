#!/usr/bin/env bash
# run_act_tests.sh — end-to-end test harness that runs EVERY test case
# through the GitHub Actions workflow via act (nektos/act).
#
# For each test case it:
#   1. builds a temp git repo containing the project files plus that case's
#      fixture data placed in test-results/ (the workflow's $RESULTS_DIR),
#   2. runs `act push --rm`, appending the full output to act-result.txt,
#   3. asserts act exited 0, that BOTH workflow jobs report "Job succeeded",
#      and that the aggregated summary contains the EXACT expected values
#      for that case's input (totals, duration, flaky/failed test rows).
#
# The bats suite (unit tests + workflow structure tests) also executes
# inside the workflow's bats-tests job, so every test runs through act.

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"

FAILURES=0
CLEANUP_DIRS=()

cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

log() { printf '%s\n' "$*"; }

fail() {
  log "  ASSERT FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

pass() { log "  assert ok: $*"; }

# run_case NAME FIXTURE_SUBDIR EXPECTED_STRING...
#
# Builds the temp repo, runs act, records output, and asserts on it.
run_case() {
  local name="$1" fixture_subdir="$2"
  shift 2
  local -a expected=("$@")

  log "== act test case: $name (fixtures: $fixture_subdir) =="

  local tmp
  tmp="$(mktemp -d)"
  CLEANUP_DIRS+=("$tmp")

  # Project files the workflow needs, plus this case's fixture data in
  # test-results/ where the workflow's aggregate job picks it up.
  cp -r "$ROOT/aggregate-test-results.sh" "$ROOT/run_act_tests.sh" \
        "$ROOT/tests" "$ROOT/fixtures" "$ROOT/.github" "$tmp/"
  [[ -f "$ROOT/.actrc" ]] && cp "$ROOT/.actrc" "$tmp/"
  mkdir -p "$tmp/test-results"
  cp "$ROOT/fixtures/$fixture_subdir"/* "$tmp/test-results/"

  (
    cd "$tmp"
    git init -q
    git add -A
    git -c user.email=harness@example.com -c user.name="act harness" \
        commit -qm "act test case: $name"
  )

  # Run the workflow. --pull=false keeps act on the locally available
  # runner image (also pinned via -P in case no .actrc was copied);
  # --rm cleans up job containers.
  local rc=0 output
  output="$(cd "$tmp" && act push --rm --pull=false \
    -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1)" || rc=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $name (fixtures: $fixture_subdir)"
    echo "================================================================"
    printf '%s\n' "$output"
    echo "--- act exit code for '$name': $rc ---"
    echo
  } >>"$RESULT_FILE"

  # Assertion 1: act itself succeeded.
  if [[ $rc -eq 0 ]]; then
    pass "act exited 0"
  else
    fail "act exited $rc (expected 0)"
  fi

  # Assertion 2: every job (bats-tests + aggregate) reports success.
  local succeeded
  succeeded="$(grep -c 'Job succeeded' <<<"$output" || true)"
  if [[ "$succeeded" -eq 2 ]]; then
    pass "both jobs report 'Job succeeded'"
  else
    fail "expected 2 'Job succeeded' lines, saw $succeeded"
  fi

  # Assertion 3: exact expected values for this case's input data.
  local e
  for e in "${expected[@]}"; do
    if grep -qF -- "$e" <<<"$output"; then
      pass "output contains: $e"
    else
      fail "output missing expected value: $e"
    fi
  done
}

main() {
  command -v act >/dev/null || { echo "ERROR: act is not installed" >&2; exit 1; }
  command -v docker >/dev/null || { echo "ERROR: docker is not installed" >&2; exit 1; }

  : >"$RESULT_FILE"

  # Case 1: matrix with a flaky test (math.test_div passes in run2 but
  # fails in run1) and a consistently failing test (ui.test_click).
  # Known-good totals: 12 tests = 7 passed + 2 failed + 3 skipped,
  # duration 2.0 + 1.85 + 3.1 = 6.95s.
  # shellcheck disable=SC2016  # backticks below are literal markdown, not expansions
  run_case "matrix-with-flaky-tests" "matrix-flaky" \
    "| Total tests | 12 |" \
    "| ✅ Passed | 7 |" \
    "| ❌ Failed | 2 |" \
    "| ⏭️ Skipped | 3 |" \
    "| ⏱️ Duration | 6.95s |" \
    '| `math.test_div` | 1 | 1 |' \
    '| `math.test_div` | run1-junit.xml |' \
    '| `ui.test_click` | run3.json |' \
    "Aggregated **3** result file(s)"

  # Case 2: all-green matrix — no flaky tests, no failures.
  # Known-good totals: 4 tests, all passed, 0.5 + 0.5 = 1.00s.
  run_case "all-green-matrix" "all-pass" \
    "| Total tests | 4 |" \
    "| ✅ Passed | 4 |" \
    "| ❌ Failed | 0 |" \
    "| ⏭️ Skipped | 0 |" \
    "| ⏱️ Duration | 1.00s |" \
    "No flaky tests detected" \
    "No failed tests" \
    "Aggregated **2** result file(s)"

  echo
  if [[ $FAILURES -eq 0 ]]; then
    log "ALL ACT TEST CASES PASSED (full act output: $RESULT_FILE)"
  else
    log "$FAILURES ASSERTION(S) FAILED (full act output: $RESULT_FILE)"
    exit 1
  fi
}

main "$@"
