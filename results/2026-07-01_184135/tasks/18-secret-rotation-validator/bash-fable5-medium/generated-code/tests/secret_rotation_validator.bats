#!/usr/bin/env bats
# Tests for secret-rotation-validator.sh
#
# TDD approach: each test was written BEFORE the functionality it covers.
# All date-dependent tests pin "now" with --now so results are deterministic.

setup() {
  # Resolve repo root relative to this test file so bats can run from anywhere.
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/secret-rotation-validator.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  # Fixed reference date used by every classification test.
  NOW="2026-07-01"
}

# --- CLI contract -----------------------------------------------------------

@test "prints usage with --help and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--warning-days"* ]]
  [[ "$output" == *"--format"* ]]
}

@test "fails with meaningful error when config file is missing" {
  run "$SCRIPT" --config /nonexistent/secrets.json --now "$NOW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: config file not found: /nonexistent/secrets.json"* ]]
}

@test "rejects unknown options" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: unknown option: --bogus"* ]]
}

# --- Input validation -------------------------------------------------------

@test "fails with meaningful error on invalid JSON" {
  run "$SCRIPT" --config "$FIXTURES/invalid.json" --now "$NOW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: invalid JSON in config file:"* ]]
}

@test "fails when a secret is missing a required field" {
  run "$SCRIPT" --config "$FIXTURES/missing-field.json" --now "$NOW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: secret 'broken-secret' is missing or has invalid 'rotation_days'"* ]]
}

@test "fails when last_rotated is not a valid date" {
  run "$SCRIPT" --config "$FIXTURES/bad-date.json" --now "$NOW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: secret 'weird-secret' has invalid last_rotated date: not-a-date"* ]]
}

@test "fails on invalid --format" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --format xml
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: invalid format: xml (expected 'markdown' or 'json')"* ]]
}

@test "fails on non-numeric --warning-days" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days soon
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: invalid warning-days: soon (expected a non-negative integer)"* ]]
}

@test "fails on invalid --now date" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now yesterday-ish
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: invalid --now date: yesterday-ish"* ]]
}

# --- Classification (markdown output, now pinned to 2026-07-01) -------------
# mixed.json expectations with warning window 14 days:
#   db-password: expired 2026-04-01 (91 days overdue)
#   api-key:     expires 2026-07-10 (9 days left -> warning)
#   tls-cert:    expires 2027-06-01 (335 days left -> ok)

@test "markdown report classifies expired, warning and ok secrets" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days 14
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 🔴 EXPIRED (1)"* ]]
  [[ "$output" == *"## 🟡 WARNING (1)"* ]]
  [[ "$output" == *"## 🟢 OK (1)"* ]]
  [[ "$output" == *"| db-password | 2026-01-01 | 90 | 2026-04-01 | 91 | api, worker |"* ]]
  [[ "$output" == *"| api-key | 2026-06-10 | 30 | 2026-07-10 | 9 | gateway |"* ]]
  [[ "$output" == *"| tls-cert | 2026-06-01 | 365 | 2027-06-01 | 335 | ingress |"* ]]
}

@test "markdown report includes header with reference date and window" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days 14
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
  [[ "$output" == *"Reference date: 2026-07-01 | Warning window: 14 days"* ]]
}

@test "secret expiring today is classified as expired" {
  run "$SCRIPT" --config "$FIXTURES/expires-today.json" --now "$NOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 🔴 EXPIRED (1)"* ]]
  [[ "$output" == *"| edge-secret | 2026-06-01 | 30 | 2026-07-01 | 0 | cron |"* ]]
}

# --- JSON output ------------------------------------------------------------

@test "json output is valid JSON with correct grouping and counts" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days 14 --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  [ "$(echo "$output" | jq -r '.reference_date')" = "2026-07-01" ]
  [ "$(echo "$output" | jq -r '.warning_days')" = "14" ]
  [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
}

@test "json output contains exact per-secret records" {
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days 14 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.expired[0]')" = '{"name":"db-password","last_rotated":"2026-01-01","rotation_days":90,"expires_on":"2026-04-01","days_left":-91,"required_by":["api","worker"]}' ]
  [ "$(echo "$output" | jq -c '.warning[0]')" = '{"name":"api-key","last_rotated":"2026-06-10","rotation_days":30,"expires_on":"2026-07-10","days_left":9,"required_by":["gateway"]}' ]
  [ "$(echo "$output" | jq -c '.ok[0]')" = '{"name":"tls-cert","last_rotated":"2026-06-01","rotation_days":365,"expires_on":"2027-06-01","days_left":335,"required_by":["ingress"]}' ]
}

@test "empty secrets list produces an all-zero report in both formats" {
  run "$SCRIPT" --config "$FIXTURES/empty.json" --now "$NOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 🔴 EXPIRED (0)"* ]]
  [[ "$output" == *"_None._"* ]]

  run "$SCRIPT" --config "$FIXTURES/empty.json" --now "$NOW" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.expired + .warning + .ok')" = "[]" ]
}

@test "warning window is configurable" {
  # With a 30-day window even tls-cert stays ok, but api-key (9 days left)
  # and a 20-day-out secret would warn; with window 5, api-key becomes ok.
  run "$SCRIPT" --config "$FIXTURES/mixed.json" --now "$NOW" --warning-days 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 🟡 WARNING (0)"* ]]
  [[ "$output" == *"## 🟢 OK (2)"* ]]
}
