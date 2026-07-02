#!/usr/bin/env bash
#
# run_act_tests.sh — end-to-end test harness that drives every test case
# through the GitHub Actions workflow with nektos/act.
#
# For each case it:
#   1. builds a temp git repo containing the project files plus that case's
#      ci-input fixture data,
#   2. runs `act push --rm` inside it,
#   3. appends the full act output to act-result.txt (clearly delimited),
#   4. asserts act exited 0, both jobs succeeded, and the report contains
#      the exact expected values for that case's input.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$ROOT_DIR/act-result.txt"
FIXTURES="$ROOT_DIR/test/fixtures"
FAILURES=0

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Fail the harness with a readable message.
fail() {
  echo "ASSERT FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

# Assert that a file contains a fixed string (tabs included, no regex).
assert_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    echo "  ok: output contains '$needle'"
  else
    fail "expected act output to contain: '$needle'"
  fi
}

assert_not_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    fail "expected act output NOT to contain: '$needle'"
  else
    echo "  ok: output does not contain '$needle'"
  fi
}

# Build a disposable git repo with the project files + one case's ci-input.
# Args: dest-dir, then "src:dest" pairs for the ci-input files.
make_case_repo() {
  local dest="$1"; shift
  mkdir -p "$dest/ci-input"
  cp -r "$ROOT_DIR/.github" "$ROOT_DIR/test" "$dest/"
  cp "$ROOT_DIR/license-checker.sh" "$ROOT_DIR/.actrc" "$dest/"
  local pair
  for pair in "$@"; do
    cp "${pair%%:*}" "$dest/ci-input/${pair##*:}"
  done
  git -C "$dest" init -q -b main
  git -C "$dest" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$dest" -c user.email=ci@example.com -c user.name=ci commit -qm "test case"
}

# Run act for one case, capture output, and run the shared assertions.
# Sets CASE_LOG to the captured output file for case-specific assertions.
run_case() {
  local title="$1" repo="$2"
  CASE_LOG="$TMP_ROOT/$(basename "$repo").log"

  echo "=== $title ==="
  local rc=0
  (cd "$repo" && act push --rm --pull=false) >"$CASE_LOG" 2>&1 || rc=$?

  {
    printf '==================== %s ====================\n' "$title"
    cat "$CASE_LOG"
    printf '\n'
  } >> "$RESULT_FILE"

  if [[ "$rc" -eq 0 ]]; then
    echo "  ok: act exited 0"
  else
    fail "act exited $rc for case: $title"
  fi

  # Both jobs (test + license-check) must report success.
  local succeeded
  succeeded="$(grep -c 'Job succeeded' "$CASE_LOG" || true)"
  if [[ "$succeeded" -eq 2 ]]; then
    echo "  ok: both jobs succeeded"
  else
    fail "expected 2 'Job succeeded' lines, got $succeeded"
  fi

  # The in-container bats suite must run all 15 tests with zero failures.
  assert_contains "$CASE_LOG" "1..15"
  assert_not_contains "$CASE_LOG" "not ok"
}

: > "$RESULT_FILE"  # start a fresh result artifact

# --- Case 1: npm manifest, denied license present, report-only mode ---------
repo1="$TMP_ROOT/case1-npm"
make_case_repo "$repo1" \
  "$FIXTURES/package.json:package.json" \
  "$FIXTURES/config.txt:config.txt" \
  "$FIXTURES/licenses.tsv:licenses.tsv"
run_case "TEST CASE 1: npm manifest with denied license (report-only)" "$repo1"
assert_contains "$CASE_LOG" "$(printf 'express\t^4.18.2\tMIT\tapproved')"
assert_contains "$CASE_LOG" "$(printf 'left-pad\t1.3.0\tWTFPL\tunknown')"
assert_contains "$CASE_LOG" "$(printf 'evil-lib\t2.0.0\tGPL-3.0\tdenied')"
assert_contains "$CASE_LOG" "$(printf 'mystery-lib\t0.0.1\tUNKNOWN\tunknown')"
assert_contains "$CASE_LOG" "SUMMARY: total=4 approved=1 denied=1 unknown=2"
assert_contains "$CASE_LOG" "RESULT: FAIL"

# --- Case 2: pip manifest, everything on the allow-list, PASS ---------------
repo2="$TMP_ROOT/case2-pip"
make_case_repo "$repo2" \
  "$FIXTURES/clean-requirements.txt:requirements.txt" \
  "$FIXTURES/config.txt:config.txt" \
  "$FIXTURES/licenses.tsv:licenses.tsv"
run_case "TEST CASE 2: clean pip manifest (all approved)" "$repo2"
assert_contains "$CASE_LOG" "$(printf 'flask\t2.3.2\tBSD-3-Clause\tapproved')"
assert_contains "$CASE_LOG" "$(printf 'requests\t2.31.0\tApache-2.0\tapproved')"
assert_contains "$CASE_LOG" "$(printf 'pyyaml\t6.0\tMIT\tapproved')"
assert_contains "$CASE_LOG" "SUMMARY: total=3 approved=3 denied=0 unknown=0"
assert_contains "$CASE_LOG" "RESULT: PASS"
assert_not_contains "$CASE_LOG" "RESULT: FAIL"

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "ACT E2E: $FAILURES assertion(s) failed (see $RESULT_FILE)"
  exit 1
fi
echo "ACT E2E: all assertions passed (output in $RESULT_FILE)"
