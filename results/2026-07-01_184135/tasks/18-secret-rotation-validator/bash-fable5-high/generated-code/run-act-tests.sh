#!/usr/bin/env bash
# End-to-end test harness: every test case runs THROUGH the GitHub Actions
# workflow via act (nektos/act), never against the script directly.
#
# For each test case we:
#   1. Build a temp git repo containing the project files, with that case's
#      fixture data installed as config/secrets.json.
#   2. Run `act push --rm` and append the full output to act-result.txt
#      (clearly delimited per case).
#   3. Assert act exited 0, that both workflow jobs report "Job succeeded",
#      that the in-pipeline bats suite ran all tests with zero failures, and
#      that the report output matches EXACT known-good values for the fixture.
#
# All expectations are computed by hand from the fixture dates against the
# workflow's pinned REFERENCE_DATE (2026-07-01).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
FAILURES=0
CHECKS=0

: > "$RESULT_FILE"

cleanup() { [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"; }
trap cleanup EXIT
WORK_DIR="$(mktemp -d)"

# Assert that the captured act output for the current case contains an exact
# expected line/fragment.
assert_contains() {
  local file="$1" expected="$2"
  CHECKS=$((CHECKS + 1))
  if grep -qF -- "$expected" "$file"; then
    echo "  PASS: found: $expected"
  else
    echo "  FAIL: missing expected output: $expected"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  CHECKS=$((CHECKS + 1))
  if grep -qF -- "$unexpected" "$file"; then
    echo "  FAIL: found unexpected output: $unexpected"
    FAILURES=$((FAILURES + 1))
  else
    echo "  PASS: absent as expected: $unexpected"
  fi
}

assert_count() {
  local file="$1" needle="$2" want="$3" got
  CHECKS=$((CHECKS + 1))
  got="$(grep -cF -- "$needle" "$file" || true)"
  if [[ "$got" -eq "$want" ]]; then
    echo "  PASS: '$needle' appears $want time(s)"
  else
    echo "  FAIL: '$needle' appears $got time(s), expected $want"
    FAILURES=$((FAILURES + 1))
  fi
}

# Run one test case through the workflow. $1 = case name, $2 = fixture file
# to install as config/secrets.json. Captured output lands in $CASE_LOG.
run_case() {
  local case_name="$1" fixture="$2"
  local repo="$WORK_DIR/$case_name"
  CASE_LOG="$WORK_DIR/$case_name.log"

  echo "=== case: $case_name (fixture: $(basename "$fixture")) ==="

  mkdir -p "$repo/config"
  cp -r "$PROJECT_ROOT/.github" "$PROJECT_ROOT/tests" "$repo/"
  cp "$PROJECT_ROOT/secret-rotation-validator.sh" "$repo/"
  cp "$PROJECT_ROOT/.actrc" "$repo/" 2>/dev/null || true
  cp "$fixture" "$repo/config/secrets.json"

  git -C "$repo" init -q
  git -C "$repo" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$repo" -c user.email=ci@example.com -c user.name=ci commit -qm "test case $case_name"

  local act_status=0
  (cd "$repo" && act push --rm --pull=false \
      -P ubuntu-latest=act-ubuntu-pwsh:latest) > "$CASE_LOG" 2>&1 || act_status=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $case_name"
    echo "=== fixture:   $(basename "$fixture")"
    echo "=== act exit:  $act_status"
    echo "================================================================"
    cat "$CASE_LOG"
    echo
  } >> "$RESULT_FILE"

  CHECKS=$((CHECKS + 1))
  if [[ "$act_status" -eq 0 ]]; then
    echo "  PASS: act exited 0"
  else
    echo "  FAIL: act exited $act_status"
    FAILURES=$((FAILURES + 1))
  fi

  # Both jobs (test + report) must succeed, and nothing may fail.
  assert_count "$CASE_LOG" "Job succeeded" 2
  assert_not_contains "$CASE_LOG" "Job failed"
  # The full bats suite ran inside the pipeline with zero failures.
  assert_contains "$CASE_LOG" "1..31"
  assert_not_contains "$CASE_LOG" "not ok"
}

# --- Case 1: mixed urgencies -------------------------------------------------
# Fixture tests/fixtures/secrets.json vs REFERENCE_DATE 2026-07-01, warn 14d:
#   db-password rotated 2026-03-01 + 90d  -> expired 2026-05-30, 32d overdue
#   api-key     rotated 2026-06-10 + 30d  -> warning, expires 2026-07-10 (9d)
#   tls-cert    rotated 2026-06-20 + 365d -> ok, expires 2027-06-20 (354d)
run_case "mixed-urgencies" "$PROJECT_ROOT/tests/fixtures/secrets.json"
assert_contains "$CASE_LOG" "SUMMARY expired=1 warning=1 ok=1 total=3"
assert_contains "$CASE_LOG" "NOTIFY[expired] db-password expires_on=2026-05-30 days_left=-32 required_by=billing-api,reporting"
assert_contains "$CASE_LOG" "NOTIFY[warning] api-key expires_on=2026-07-10 days_left=9 required_by=gateway"
assert_contains "$CASE_LOG" "NOTIFY[ok] tls-cert expires_on=2027-06-20 days_left=354 required_by=frontend,cdn"
assert_contains "$CASE_LOG" "| db-password | 2026-03-01 | 90 | 2026-05-30 | -32 | billing-api, reporting |"
assert_contains "$CASE_LOG" "| api-key | 2026-06-10 | 30 | 2026-07-10 | 9 | gateway |"
assert_contains "$CASE_LOG" "| tls-cert | 2026-06-20 | 365 | 2027-06-20 | 354 | frontend, cdn |"
assert_contains "$CASE_LOG" "## 🔴 EXPIRED (1)"
assert_contains "$CASE_LOG" "## 🟡 WARNING (1)"
assert_contains "$CASE_LOG" "## 🟢 OK (1)"
assert_contains "$CASE_LOG" "- **Totals:** 1 expired, 1 warning, 1 ok (3 total)"

# --- Case 2: boundary conditions ---------------------------------------------
# Fixture tests/fixtures/boundary.json vs REFERENCE_DATE 2026-07-01, warn 14d:
#   expires-today rotated 2026-06-01 + 30d -> expires 2026-07-01 = today
#                 -> days_left 0 -> EXPIRED (expiry day counts as expired)
#   warn-edge     rotated 2026-06-17 + 28d -> expires 2026-07-15
#                 -> days_left 14 = warn window edge -> WARNING
run_case "boundary-conditions" "$PROJECT_ROOT/tests/fixtures/boundary.json"
assert_contains "$CASE_LOG" "SUMMARY expired=1 warning=1 ok=0 total=2"
assert_contains "$CASE_LOG" "NOTIFY[expired] expires-today expires_on=2026-07-01 days_left=0 required_by=svc-a"
assert_contains "$CASE_LOG" "NOTIFY[warning] warn-edge expires_on=2026-07-15 days_left=14 required_by=svc-b"
assert_contains "$CASE_LOG" "| expires-today | 2026-06-01 | 30 | 2026-07-01 | 0 | svc-a |"
assert_contains "$CASE_LOG" "| warn-edge | 2026-06-17 | 28 | 2026-07-15 | 14 | svc-b |"
assert_contains "$CASE_LOG" "## 🟢 OK (0)"
assert_contains "$CASE_LOG" "- **Totals:** 1 expired, 1 warning, 0 ok (2 total)"

# --- Summary -------------------------------------------------------------------
echo
echo "act harness: $((CHECKS - FAILURES))/$CHECKS assertions passed"
echo "full act output saved to: $RESULT_FILE"
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: FAIL ($FAILURES assertion(s) failed)"
  exit 1
fi
echo "RESULT: PASS"
