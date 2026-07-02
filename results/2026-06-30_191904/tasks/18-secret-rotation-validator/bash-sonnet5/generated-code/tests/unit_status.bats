#!/usr/bin/env bats
# Unit tests for augment_secret(): given one secret (as compact JSON) plus a
# warning window and a reference "today", it must compute days_since_rotation,
# expires_in_days, next_rotation_date, and classify status as one of
# expired | warning | ok. Boundaries: expires_in <= 0 => expired,
# 0 < expires_in <= warning_days => warning, else ok.

setup() {
  source "$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
}

@test "augment_secret classifies a long-overdue secret as expired" {
  local secret='{"name":"DB_PASSWORD","last_rotated":"2026-01-01","rotation_days":90,"required_by":["billing-api"]}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "expired" ]
  [ "$(jq -r '.days_since_rotation' <<<"$output")" = "165" ]
  [ "$(jq -r '.expires_in_days' <<<"$output")" = "-75" ]
  [ "$(jq -r '.next_rotation_date' <<<"$output")" = "2026-04-01" ]
}

@test "augment_secret classifies a secret due within the warning window as warning" {
  local secret='{"name":"API_KEY","last_rotated":"2026-05-20","rotation_days":30,"required_by":["payments-gateway"]}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "warning" ]
  [ "$(jq -r '.expires_in_days' <<<"$output")" = "4" ]
}

@test "augment_secret classifies a freshly-rotated secret as ok" {
  local secret='{"name":"TLS_CERT","last_rotated":"2026-06-10","rotation_days":365,"required_by":["edge-proxy"]}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "ok" ]
  [ "$(jq -r '.expires_in_days' <<<"$output")" = "360" ]
}

@test "augment_secret treats expires_in_days exactly equal to the warning window as warning" {
  local secret='{"name":"WEBHOOK_SECRET","last_rotated":"2026-05-15","rotation_days":45,"required_by":["notification-service"]}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expires_in_days' <<<"$output")" = "14" ]
  [ "$(jq -r '.status' <<<"$output")" = "warning" ]
}

@test "augment_secret treats expires_in_days exactly zero as expired" {
  local secret='{"name":"OAUTH_CLIENT_SECRET","last_rotated":"2026-03-17","rotation_days":90,"required_by":["auth-service"]}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expires_in_days' <<<"$output")" = "0" ]
  [ "$(jq -r '.status' <<<"$output")" = "expired" ]
}

@test "augment_secret defaults required_by to an empty array when absent" {
  local secret='{"name":"SMTP_PASSWORD","last_rotated":"2026-06-14","rotation_days":60}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.required_by | length' <<<"$output")" = "0" ]
}

@test "augment_secret fails on an invalid last_rotated date" {
  local secret='{"name":"BAD_DATE","last_rotated":"06/15/2026","rotation_days":30}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BAD_DATE"* ]]
}

@test "augment_secret fails on a non-positive rotation_days" {
  local secret='{"name":"ZERO_ROTATION","last_rotated":"2026-01-01","rotation_days":0}'
  run augment_secret "$secret" 14 "2026-06-15"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ZERO_ROTATION"* ]]
}
