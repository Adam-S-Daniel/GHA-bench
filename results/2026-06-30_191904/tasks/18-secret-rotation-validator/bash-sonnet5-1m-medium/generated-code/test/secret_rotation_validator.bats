#!/usr/bin/env bats
# Unit-level tests for scripts/secret_rotation_validator.sh.
# These tests invoke the script directly as a subprocess (not sourcing
# internals) so they exercise the same interface real callers use.
# Fixed --today value keeps every assertion deterministic.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/secret_rotation_validator.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"
  TODAY="2026-07-01"
}

@test "script file exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "script passes bash -n syntax check" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "missing --config errors with meaningful message" {
  run "$SCRIPT" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--config"* ]]
}

@test "nonexistent config file errors with meaningful message" {
  run "$SCRIPT" --config "$FIXTURES/does-not-exist.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "unknown option errors with meaningful message" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --bogus-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "invalid --format errors with meaningful message" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format yaml
  [ "$status" -ne 0 ]
  [[ "$output" == *"format"* ]]
}

@test "malformed JSON config errors with meaningful message" {
  run "$SCRIPT" --config "$FIXTURES/secrets_invalid.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not-a-date"* || "$output" == *"date"* ]]
}

@test "config entry missing required field errors with meaningful message" {
  run "$SCRIPT" --config "$FIXTURES/secrets_missing_field.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rotation_days"* ]]
}

@test "markdown report classifies expired, warning and ok secrets correctly" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format markdown
  [ "$status" -eq 0 ]
  # db-password: rotated 2026-01-01 + 90d = 2026-04-01, well past today -> EXPIRED
  [[ "$output" == *"db-password"*"EXPIRED"* ]]
  # api-key: rotated 2026-06-04 + 30d = 2026-07-04, 3 days out, within default 7-day window -> WARNING
  [[ "$output" == *"api-key"*"WARNING"* ]]
  # tls-cert: rotated 2026-06-29 + 365d, far in the future -> OK
  [[ "$output" == *"tls-cert"*"OK"* ]]
  [[ "$output" == *"Expired"* ]]
  [[ "$output" == *"Warning"* ]]
}

@test "markdown report includes required_by services" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"api"* ]]
  [[ "$output" == *"worker"* ]]
  [[ "$output" == *"frontend"* ]]
}

@test "json report produces valid JSON with correct summary counts" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.total')" = "3" ]
}

@test "json report has exact per-secret status and days_until_expiry" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .status')" = "expired" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')" = "warning" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .days_until_expiry')" = "3" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="tls-cert") | .status')" = "ok" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="tls-cert") | .expiry_date')" = "2027-06-29" ]
}

@test "json report groups secret names by urgency" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.groups.expired[0]')" = "db-password" ]
  [ "$(echo "$output" | jq -r '.groups.warning[0]')" = "api-key" ]
  [ "$(echo "$output" | jq -r '.groups.ok[0]')" = "tls-cert" ]
}

@test "boundary case: expiry exactly today counts as expired" {
  run "$SCRIPT" --config "$FIXTURES/secrets_edge_boundary.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="session-token") | .status')" = "expired" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="session-token") | .days_until_expiry')" = "0" ]
}

@test "boundary case: expiry exactly at warning-days threshold counts as warning" {
  run "$SCRIPT" --config "$FIXTURES/secrets_edge_boundary.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="webhook-secret") | .status')" = "warning" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="webhook-secret") | .days_until_expiry')" = "7" ]
}

@test "custom --warning-days widens the warning window" {
  run "$SCRIPT" --config "$FIXTURES/secrets_mixed.json" --today "$TODAY" --format json --warning-days 30
  [ "$status" -eq 0 ]
  # api-key (3 days out) and tls-cert stays ok, but db-password already expired stays expired.
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')" = "warning" ]
  [ "$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .status')" = "expired" ]
}

@test "all-ok config reports zero expired and zero warning" {
  run "$SCRIPT" --config "$FIXTURES/secrets_all_ok.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.expired')" = "0" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "0" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "2" ]
}
