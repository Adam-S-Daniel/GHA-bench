#!/usr/bin/env bats
#
# End-to-end tests for the validator CLI: report generation, output formats,
# urgency grouping, summary counts and error handling.
#
# These run the script as a subprocess (not sourced) so they exercise the real
# argument parsing and main() flow. A fixed --now makes results deterministic.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../secret-rotation-validator.sh"
  FIX="${BATS_TEST_DIRNAME}/../fixtures/secrets.json"
}

# --- JSON format -----------------------------------------------------------

@test "json: summary counts are correct for the fixture" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.summary.expired')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.warning')" = "1" ]
  [ "$(echo "$output" | jq -r '.summary.ok')" = "1" ]
}

@test "json: db-password is expired with negative days_until_due" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format json
  [ "$status" -eq 0 ]
  local s
  s=$(echo "$output" | jq -r '.secrets[] | select(.name=="db-password")')
  [ "$(echo "$s" | jq -r '.status')" = "expired" ]
  [ "$(echo "$s" | jq -r '.days_until_due')" = "-10" ]
  [ "$(echo "$s" | jq -r '.age_days')" = "40" ]
}

@test "json: stripe-api-key is warning with correct required_by" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format json
  [ "$status" -eq 0 ]
  local s
  s=$(echo "$output" | jq -r '.secrets[] | select(.name=="stripe-api-key")')
  [ "$(echo "$s" | jq -r '.status')" = "warning" ]
  [ "$(echo "$s" | jq -r '.days_until_due')" = "9" ]
  [ "$(echo "$s" | jq -r '.required_by | join(",")')" = "billing-api" ]
}

@test "json: generated_for and warning_days echo the inputs" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.generated_for')" = "2024-02-10" ]
  [ "$(echo "$output" | jq -r '.warning_days')" = "14" ]
}

# --- Markdown format -------------------------------------------------------

@test "markdown: contains header and summary line" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
  [[ "$output" == *"Summary: 1 expired, 1 warning, 1 ok"* ]]
}

@test "markdown: groups secrets under the right urgency sections" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --warning-days 14 --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Expired (1)"* ]]
  [[ "$output" == *"## Warning (1)"* ]]
  [[ "$output" == *"## OK (1)"* ]]
  [[ "$output" == *"| db-password |"* ]]
  [[ "$output" == *"billing-api, reporting-worker"* ]]
}

@test "markdown is the default format" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
}

# --- Error handling --------------------------------------------------------

@test "error: missing config file exits non-zero with message" {
  run "$SCRIPT" --config /no/such/file.json --now 2024-02-10
  [ "$status" -ne 0 ]
  [[ "$output" == *"config file not found"* ]]
}

@test "error: invalid JSON config is reported" {
  tmp="$(mktemp)"
  echo "not json {" > "$tmp"
  run "$SCRIPT" --config "$tmp" --now 2024-02-10
  rm -f "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "error: non-array JSON root is rejected" {
  tmp="$(mktemp)"
  echo '{"name":"x"}' > "$tmp"
  run "$SCRIPT" --config "$tmp" --now 2024-02-10
  rm -f "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a JSON array"* ]]
}

@test "error: bad warning-days is rejected" {
  run "$SCRIPT" --config "$FIX" --warning-days abc --now 2024-02-10
  [ "$status" -ne 0 ]
  [[ "$output" == *"warning-days"* ]]
}

@test "error: unknown format is rejected" {
  run "$SCRIPT" --config "$FIX" --now 2024-02-10 --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown format"* ]]
}
