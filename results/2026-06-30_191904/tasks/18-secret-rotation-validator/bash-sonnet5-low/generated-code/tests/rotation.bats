#!/usr/bin/env bats
# Tests for scripts/secret-rotation-validator.sh
# Uses a fixed --today date so classification results are deterministic.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/secret-rotation-validator.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"
  TODAY="2026-07-01"
}

@test "script file exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "fails with meaningful error when config file is missing" {
  run "$SCRIPT" --config "${FIXTURES}/does-not-exist.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "fails with meaningful error on invalid JSON" {
  run "$SCRIPT" --config "${FIXTURES}/invalid.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "fails with meaningful error when a secret is missing required fields" {
  run "$SCRIPT" --config "${FIXTURES}/missing_field.json" --today "$TODAY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required field"* ]]
}

@test "classifies an expired secret" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .status')
  [ "$status_val" = "expired" ]
}

@test "classifies a warning secret within the warning window" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')
  days_left=$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .days_left')
  [ "$status_val" = "warning" ]
  [ "$days_left" = "19" ]
}

@test "classifies an ok secret outside the warning window" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.secrets[] | select(.name=="tls-cert") | .status')
  [ "$status_val" = "ok" ]
}

@test "a smaller warning window reclassifies api-key as ok" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 5 --format json
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')
  [ "$status_val" = "ok" ]
}

@test "json output includes correct summary counts" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.summary.expired == 1' >/dev/null
  echo "$output" | jq -e '.summary.warning == 1' >/dev/null
  echo "$output" | jq -e '.summary.ok == 1' >/dev/null
}

@test "json output is valid json" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
}

@test "json output preserves required_by list" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format json
  [ "$status" -eq 0 ]
  req=$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password") | .required_by | join(",")')
  [ "$req" = "api,worker" ]
}

@test "markdown output contains a table header and rows for each urgency group" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Name | Status"* ]]
  [[ "$output" == *"db-password"* ]]
  [[ "$output" == *"api-key"* ]]
  [[ "$output" == *"tls-cert"* ]]
  [[ "$output" == *"## Expired"* ]]
  [[ "$output" == *"## Warning"* ]]
  [[ "$output" == *"## OK"* ]]
}

@test "default output format is markdown when --format is not given" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days 21
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Name | Status"* ]]
}

@test "rejects an unsupported output format" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported format"* ]]
}

@test "rejects a non-numeric warning-days value" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --warning-days abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"warning-days must be a non-negative integer"* ]]
}

@test "default warning-days is 14 when not specified" {
  run "$SCRIPT" --config "${FIXTURES}/secrets_basic.json" --today "$TODAY" --format json
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.secrets[] | select(.name=="api-key") | .status')
  # api-key has 19 days left; default window of 14 means it is NOT in warning
  [ "$status_val" = "ok" ]
}
