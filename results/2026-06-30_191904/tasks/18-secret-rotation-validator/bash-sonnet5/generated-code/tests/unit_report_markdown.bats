#!/usr/bin/env bats
# Unit tests for render_markdown(): renders the JSON report (as produced by
# generate_report_json) into a markdown document with a summary table and
# one table per urgency bucket.

setup() {
  source "$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
  fixtures="$BATS_TEST_DIRNAME/../fixtures"
  report=$(generate_report_json "$fixtures/secrets-mixed.json" 14 "2026-06-15")
}

@test "render_markdown includes a title and the reference date" {
  run render_markdown "$report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
  [[ "$output" == *"2026-06-15"* ]]
}

@test "render_markdown includes a summary table with correct counts" {
  run render_markdown "$report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Expired | 2 |"* ]]
  [[ "$output" == *"| Warning | 2 |"* ]]
  [[ "$output" == *"| OK | 1 |"* ]]
}

@test "render_markdown lists expired secrets under an Expired section" {
  run render_markdown "$report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Expired"* ]]
  [[ "$output" == *"DB_PASSWORD"* ]]
  [[ "$output" == *"OAUTH_CLIENT_SECRET"* ]]
}

@test "render_markdown lists required_by services joined by commas" {
  run render_markdown "$report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"billing-api, checkout-service"* ]]
}

@test "render_markdown prints a placeholder for an empty urgency bucket" {
  local empty_report
  empty_report=$(generate_report_json "$fixtures/secrets-all-ok.json" 14 "2026-06-15")
  run render_markdown "$empty_report"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Expired"*$'\n'*"_None_"* ]]
}
