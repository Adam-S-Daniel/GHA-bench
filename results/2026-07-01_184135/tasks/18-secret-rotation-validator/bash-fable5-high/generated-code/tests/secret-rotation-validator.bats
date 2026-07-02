#!/usr/bin/env bats
# Tests for secret-rotation-validator.sh
#
# TDD approach: each block of tests below was written BEFORE the code that
# makes it pass (red -> green -> refactor). Tests use a fixed --now date so
# results are fully deterministic regardless of when the suite runs.

setup() {
  # Directory of this test file, then the project root above it.
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(dirname "$TEST_DIR")"
  SCRIPT="$PROJECT_ROOT/secret-rotation-validator.sh"
  FIXTURES="$TEST_DIR/fixtures"
}

# --- Cycle 1: CLI / argument validation -------------------------------------

@test "fails with meaningful error when --config is missing" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--config is required"* ]]
}

@test "fails with meaningful error when config file does not exist" {
  run "$SCRIPT" --config /nonexistent/secrets.json
  [ "$status" -eq 2 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--warn-days"* ]]
  [[ "$output" == *"--format"* ]]
}

# --- Cycle 2: classification + JSON output ----------------------------------
# Fixture dates are fixed and evaluated against --now 2026-07-01:
#   db-password: rotated 2026-03-01, policy 90d  -> expired  2026-05-30 (-32d)
#   api-key:     rotated 2026-06-10, policy 30d  -> warning  2026-07-10 (+9d)
#   tls-cert:    rotated 2026-06-20, policy 365d -> ok       2027-06-20 (+354d)

@test "json output is valid JSON" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
}

@test "json output classifies an expired secret with correct dates" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets.expired[0].name')" = "db-password" ]
  [ "$(echo "$output" | jq -r '.secrets.expired[0].expires_on')" = "2026-05-30" ]
  [ "$(echo "$output" | jq -r '.secrets.expired[0].days_left')" = "-32" ]
  [ "$(echo "$output" | jq -cr '.secrets.expired[0].required_by')" = '["billing-api","reporting"]' ]
}

@test "json output classifies a warning secret within the warn window" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json
  [ "$(echo "$output" | jq -r '.secrets.warning[0].name')" = "api-key" ]
  [ "$(echo "$output" | jq -r '.secrets.warning[0].days_left')" = "9" ]
  [ "$(echo "$output" | jq -r '.secrets.warning[0].expires_on')" = "2026-07-10" ]
}

@test "json output classifies an ok secret" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json
  [ "$(echo "$output" | jq -r '.secrets.ok[0].name')" = "tls-cert" ]
  [ "$(echo "$output" | jq -r '.secrets.ok[0].days_left')" = "354" ]
}

@test "json output includes summary counts and parameters" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json
  [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
  [ "$(echo "$output" | jq -r '.reference_date')" = "2026-07-01" ]
  [ "$(echo "$output" | jq -r '.warn_days')" = "14" ]
}

@test "boundary: a secret expiring exactly today is expired, exactly at warn window is warning" {
  # expires-today: 2026-06-01 + 30d = 2026-07-01 -> days_left 0 -> expired
  # warn-edge:     2026-06-17 + 28d = 2026-07-15 -> days_left 14 -> warning
  run "$SCRIPT" --config "$FIXTURES/boundary.json" --now 2026-07-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets.expired[0].name')" = "expires-today" ]
  [ "$(echo "$output" | jq -r '.secrets.expired[0].days_left')" = "0" ]
  [ "$(echo "$output" | jq -r '.secrets.warning[0].name')" = "warn-edge" ]
  [ "$(echo "$output" | jq -r '.secrets.warning[0].days_left')" = "14" ]
}

# --- Cycle 3: markdown report output ----------------------------------------

@test "markdown is the default format and includes the report title" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
  [[ "$output" == *"**Reference date:** 2026-07-01"* ]]
  [[ "$output" == *"**Warning window:** 14 days"* ]]
}

@test "markdown groups secrets under urgency sections with counts" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format markdown
  [[ "$output" == *"## 🔴 EXPIRED (1)"* ]]
  [[ "$output" == *"## 🟡 WARNING (1)"* ]]
  [[ "$output" == *"## 🟢 OK (1)"* ]]
}

@test "markdown renders exact table rows for each secret" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format markdown
  [[ "$output" == *"| Secret | Last Rotated | Policy (days) | Expires On | Days Left | Required By |"* ]]
  [[ "$output" == *"| db-password | 2026-03-01 | 90 | 2026-05-30 | -32 | billing-api, reporting |"* ]]
  [[ "$output" == *"| api-key | 2026-06-10 | 30 | 2026-07-10 | 9 | gateway |"* ]]
  [[ "$output" == *"| tls-cert | 2026-06-20 | 365 | 2027-06-20 | 354 | frontend, cdn |"* ]]
}

@test "markdown shows a placeholder for empty urgency groups" {
  # With a 5-day window nothing is in the warning group.
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --warn-days 5
  [[ "$output" == *"## 🟡 WARNING (0)"* ]]
  [[ "$output" == *"_None_"* ]]
}

@test "custom --warn-days changes classification" {
  # With a 5-day window, api-key (9 days left) becomes ok.
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format json --warn-days 5
  [ "$(echo "$output" | jq -r '.summary.warning')" = "0" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "2" ]
}

# --- Cycle 4: validation and graceful errors ---------------------------------

@test "rejects a config that is not valid JSON" {
  run "$SCRIPT" --config "$FIXTURES/invalid.json" --now 2026-07-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "rejects a secret missing a required field, naming the secret" {
  run "$SCRIPT" --config "$FIXTURES/missing-field.json" --now 2026-07-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"orphan-token"* ]]
  [[ "$output" == *"rotation_days"* ]]
}

@test "rejects a secret with a malformed last_rotated date" {
  run "$SCRIPT" --config "$FIXTURES/bad-date.json" --now 2026-07-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"weird-date"* ]]
  [[ "$output" == *"YYYY-MM-DD"* ]]
}

@test "rejects an unsupported --format" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"unsupported format: xml"* ]]
}

@test "rejects a non-numeric --warn-days" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now 2026-07-01 --warn-days soon
  [ "$status" -eq 2 ]
  [[ "$output" == *"--warn-days must be a non-negative integer"* ]]
}

@test "rejects a malformed --now date" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --now yesterday
  [ "$status" -eq 2 ]
  [[ "$output" == *"--now must be YYYY-MM-DD"* ]]
}

@test "rejects an unknown argument" {
  run "$SCRIPT" --config "$FIXTURES/secrets.json" --frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument: --frobnicate"* ]]
}

@test "handles an empty secrets list gracefully" {
  run "$SCRIPT" --config "$FIXTURES/empty.json" --now 2026-07-01 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.total')" = "0" ]
  run "$SCRIPT" --config "$FIXTURES/empty.json" --now 2026-07-01 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 🔴 EXPIRED (0)"* ]]
}
