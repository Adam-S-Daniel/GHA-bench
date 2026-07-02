#!/usr/bin/env bash
# Act-based end-to-end test harness.
#
# For each test case:
#   1. Build a temp git repo containing the project files plus that case's
#      fixture installed as fixtures/secrets.json (the path the workflow reads).
#   2. Run `act push --rm` and append the full output to act-result.txt.
#   3. Assert act exited 0, both jobs report "Job succeeded", and the output
#      contains the EXACT expected report values for that fixture.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

FAILURES=0

# assert_contains <log-file> <exact substring>
assert_contains() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    echo "  PASS: found: $needle"
  else
    echo "  FAIL: missing expected output: $needle"
    FAILURES=$((FAILURES + 1))
  fi
}

run_case() {
  local case_name="$1" fixture="$2"
  shift 2
  local expectations=("$@")

  echo "=== Test case: $case_name (fixture: $fixture) ==="
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  # Assemble the temp repo: project files + this case's fixture data.
  mkdir -p "$tmp/.github/workflows" "$tmp/fixtures"
  cp "$ROOT/secret_rotation_validator.py" \
     "$ROOT/test_secret_rotation_validator.py" "$tmp/"
  cp "$ROOT/.github/workflows/secret-rotation-validator.yml" \
     "$tmp/.github/workflows/"
  cp "$ROOT/fixtures/$fixture" "$tmp/fixtures/secrets.json"

  git -C "$tmp" init -q
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci \
    commit -qm "test case $case_name"

  local log="$tmp/act.log"
  (cd "$tmp" && act push --rm --pull=false \
    -P ubuntu-latest=act-ubuntu-pwsh:latest) >"$log" 2>&1
  local exit_code=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $case_name (fixture: $fixture)"
    echo "=== act exit code: $exit_code"
    echo "================================================================"
    cat "$log"
    echo
  } >> "$RESULT_FILE"

  if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: act exited 0"
  else
    echo "  FAIL: act exited $exit_code"
    FAILURES=$((FAILURES + 1))
  fi

  # Both jobs (test, report) must succeed.
  local succeeded
  succeeded=$(grep -c "Job succeeded" "$log")
  if [ "$succeeded" -ge 2 ]; then
    echo "  PASS: $succeeded jobs reported 'Job succeeded'"
  else
    echo "  FAIL: expected 2 'Job succeeded' lines, got $succeeded"
    FAILURES=$((FAILURES + 1))
  fi

  local needle
  for needle in "${expectations[@]}"; do
    assert_contains "$log" "$needle"
  done
  echo
}

# --- Case 1: mixed urgencies (1 expired, 1 warning, 1 ok) -------------------
run_case "case1-mixed" "case1-mixed.json" \
  "SUMMARY expired=1 warning=1 ok=1 total=3" \
  "| EXPIRED | db-password | 2026-06-21 | -10 | billing-api, reporting |" \
  "| WARNING | api-token | 2026-07-08 | 7 | gateway |" \
  "| OK | tls-cert-key | 2026-12-16 | 168 | web-frontend |" \
  '"days_until_expiry": -10' \
  "NOTIFY [EXPIRED] db-password (expires 2026-06-21, needed by: billing-api, reporting)" \
  "NOTIFY [WARNING] api-token (expires 2026-07-08, needed by: gateway)" \
  "Ran 25 tests"

# --- Case 2: boundary dates (expires today -> expired; expires at exactly ---
# --- warn_days -> warning) ---------------------------------------------------
run_case "case2-boundaries" "case2-boundaries.json" \
  "SUMMARY expired=1 warning=1 ok=0 total=2" \
  "| EXPIRED | signing-key | 2026-07-01 | 0 | auth-service |" \
  "| WARNING | oauth-secret | 2026-07-15 | 14 | sso-proxy, mobile-app |" \
  '"days_until_expiry": 0' \
  "NOTIFY [EXPIRED] signing-key (expires 2026-07-01, needed by: auth-service)" \
  "NOTIFY [WARNING] oauth-secret (expires 2026-07-15, needed by: sso-proxy, mobile-app)" \
  "Ran 25 tests"

echo "================================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT TEST CASES PASSED (results in act-result.txt)"
  exit 0
else
  echo "$FAILURES ASSERTION(S) FAILED (results in act-result.txt)"
  exit 1
fi
