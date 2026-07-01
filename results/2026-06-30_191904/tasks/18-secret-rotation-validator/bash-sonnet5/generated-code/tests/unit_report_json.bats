#!/usr/bin/env bats
# Unit tests for generate_report_json(): orchestrates validate_config +
# augment_secret across an entire config file and assembles the final JSON
# report (summary counts + secrets grouped by urgency).

setup() {
  source "$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
  fixtures="$BATS_TEST_DIRNAME/../fixtures"
}

@test "generate_report_json reports correct summary counts for a mixed config" {
  run generate_report_json "$fixtures/secrets-mixed.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.total' <<<"$output")" = "5" ]
  [ "$(jq -r '.summary.expired' <<<"$output")" = "2" ]
  [ "$(jq -r '.summary.warning' <<<"$output")" = "2" ]
  [ "$(jq -r '.summary.ok' <<<"$output")" = "1" ]
}

@test "generate_report_json groups secrets into the correct urgency buckets" {
  run generate_report_json "$fixtures/secrets-mixed.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  local expired_names warning_names ok_names
  expired_names=$(jq -r '.secrets.expired[].name' <<<"$output" | sort | tr '\n' ',')
  warning_names=$(jq -r '.secrets.warning[].name' <<<"$output" | sort | tr '\n' ',')
  ok_names=$(jq -r '.secrets.ok[].name' <<<"$output" | sort | tr '\n' ',')
  [ "$expired_names" = "DB_PASSWORD,OAUTH_CLIENT_SECRET," ]
  [ "$warning_names" = "API_KEY,WEBHOOK_SECRET," ]
  [ "$ok_names" = "TLS_CERT," ]
}

@test "generate_report_json includes the warning window and reference date" {
  run generate_report_json "$fixtures/secrets-mixed.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.warning_window_days' <<<"$output")" = "14" ]
  [ "$(jq -r '.generated_at' <<<"$output")" = "2026-06-15" ]
}

@test "generate_report_json handles an empty secrets array" {
  run generate_report_json "$fixtures/secrets-empty.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.total' <<<"$output")" = "0" ]
  [ "$(jq -r '.secrets.expired | length' <<<"$output")" = "0" ]
}

@test "generate_report_json reports all-ok summary correctly" {
  run generate_report_json "$fixtures/secrets-all-ok.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.expired' <<<"$output")" = "0" ]
  [ "$(jq -r '.summary.warning' <<<"$output")" = "0" ]
  [ "$(jq -r '.summary.ok' <<<"$output")" = "2" ]
}

@test "generate_report_json reports all-expired summary correctly" {
  run generate_report_json "$fixtures/secrets-all-expired.json" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.expired' <<<"$output")" = "2" ]
  [ "$(jq -r '.summary.ok' <<<"$output")" = "0" ]
}

@test "generate_report_json fails and reports an error for an invalid config" {
  run generate_report_json "$fixtures/secrets-missing-field.json" 14 "2026-06-15"
  [ "$status" -ne 0 ]
  [[ "$output" == *"INCOMPLETE_SECRET"* ]]
}
