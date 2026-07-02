#!/usr/bin/env bash
#
# run-act-tests.sh — end-to-end pipeline tests via nektos/act.
#
# For each test case under act-fixtures/:
#   1. Build a throwaway git repo containing the project files plus that
#      case's fixture data (copied over fixtures/).
#   2. Run `act push --rm` against it (one act run per case, 3 total).
#   3. Append the full act log to act-result.txt (delimited per case).
#   4. Assert act exited 0, both jobs succeeded, and the log contains the
#      EXACT known-good values for that case's input.
#
# Exits non-zero on the first failed assertion.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
: > "$RESULT_FILE"

PASS=0
FAIL=0

fail() {
  echo "  ASSERT FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  echo "  assert ok: $*"
  PASS=$((PASS + 1))
}

# assert_contains <log-file> <needle> — exact substring match on the act log.
assert_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    pass "log contains: $needle"
  else
    fail "log missing expected text: $needle"
  fi
}

assert_not_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    fail "log contains forbidden text: $needle"
  else
    pass "log does not contain: $needle"
  fi
}

# run_case <case-dir> — build temp repo, run act, record output.
# Sets CASE_LOG (path) and CASE_RC (act exit code) for the caller.
run_case() {
  local case_dir="$1"
  local case_name
  case_name="$(basename "$case_dir")"
  local tmp_repo
  tmp_repo="$(mktemp -d "/tmp/act-${case_name}.XXXXXX")"

  echo "=== $case_name (repo: $tmp_repo) ==="

  # Project files + this case's fixture data (overwrites defaults).
  cp -r "$PROJECT_ROOT/.github" "$PROJECT_ROOT/tests" "$PROJECT_ROOT/fixtures" \
        "$PROJECT_ROOT/secret-rotation-validator.sh" "$PROJECT_ROOT/.actrc" \
        "$tmp_repo/"
  cp "$case_dir/secrets.json" "$tmp_repo/fixtures/secrets.json"
  cp "$case_dir/params.env"   "$tmp_repo/fixtures/params.env"

  git -C "$tmp_repo" init -q -b main
  git -C "$tmp_repo" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$tmp_repo" -c user.email=ci@example.com -c user.name=ci \
    commit -qm "fixture: $case_name"

  CASE_LOG="$tmp_repo/act.log"
  (cd "$tmp_repo" && act push --rm --pull=false) >"$CASE_LOG" 2>&1
  CASE_RC=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $case_name (act exit code: $CASE_RC)"
    echo "================================================================"
    cat "$CASE_LOG"
    echo
  } >> "$RESULT_FILE"

  if [ "$CASE_RC" -eq 0 ]; then
    pass "act exited 0"
  else
    fail "act exited $CASE_RC"
  fi

  # Both jobs (test + report) must report success.
  local succeeded
  succeeded="$(grep -c 'Job succeeded' "$CASE_LOG")"
  if [ "$succeeded" -eq 2 ]; then
    pass "both jobs succeeded"
  else
    fail "expected 2 'Job succeeded' lines, got $succeeded"
  fi

  # The bats suite runs in every case's test job: 16 tests, zero failures.
  assert_contains     "$CASE_LOG" "1..16"
  assert_contains     "$CASE_LOG" "ok 16 warning window is configurable"
  assert_not_contains "$CASE_LOG" "not ok"
}

# --- Case 1: markdown report, mixed statuses, now=2026-07-01, warn=14 -------
run_case "$PROJECT_ROOT/act-fixtures/case-1-markdown"
assert_contains "$CASE_LOG" "# Secret Rotation Report"
assert_contains "$CASE_LOG" "Reference date: 2026-07-01 | Warning window: 14 days"
assert_contains "$CASE_LOG" "## 🔴 EXPIRED (1)"
assert_contains "$CASE_LOG" "## 🟡 WARNING (1)"
assert_contains "$CASE_LOG" "## 🟢 OK (1)"
assert_contains "$CASE_LOG" "| db-password | 2026-01-01 | 90 | 2026-04-01 | 91 | api, worker |"
assert_contains "$CASE_LOG" "| api-key | 2026-06-10 | 30 | 2026-07-10 | 9 | gateway |"
assert_contains "$CASE_LOG" "| tls-cert | 2026-06-01 | 365 | 2027-06-01 | 335 | ingress |"
assert_contains "$CASE_LOG" "REPORT-OK"

# --- Case 2: JSON report, exact full document ---------------------------------
run_case "$PROJECT_ROOT/act-fixtures/case-2-json"
assert_contains "$CASE_LOG" 'COMPACT-JSON: {"reference_date":"2026-07-01","warning_days":14,"summary":{"expired":1,"warning":1,"ok":1},"expired":[{"name":"db-password","last_rotated":"2026-01-01","rotation_days":90,"expires_on":"2026-04-01","days_left":-91,"required_by":["api","worker"]}],"warning":[{"name":"api-key","last_rotated":"2026-06-10","rotation_days":30,"expires_on":"2026-07-10","days_left":9,"required_by":["gateway"]}],"ok":[{"name":"tls-cert","last_rotated":"2026-06-01","rotation_days":365,"expires_on":"2027-06-01","days_left":335,"required_by":["ingress"]}]}'
assert_contains "$CASE_LOG" "REPORT-OK"

# --- Case 3: broken config -> validator fails with a clear message ------------
run_case "$PROJECT_ROOT/act-fixtures/case-3-error"
assert_contains "$CASE_LOG" "Error: secret 'broken-secret' is missing or has invalid 'rotation_days' (expected a positive integer)"
assert_contains "$CASE_LOG" "ERROR-PATH-OK"
assert_not_contains "$CASE_LOG" "REPORT-OK"

echo
echo "act harness summary: $PASS passed, $FAIL failed"
echo "full act output: $RESULT_FILE"
[ "$FAIL" -eq 0 ]
