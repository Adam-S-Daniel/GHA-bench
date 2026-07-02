#!/usr/bin/env bats
# Unit tests for main(): CLI argument parsing, output routing (stdout vs
# --output file), format selection, defaults, error handling, and the
# expired-secrets exit code contract.
#
# Exit code contract:
#   0 - ran successfully, no expired secrets (or --no-fail-on-expired)
#   1 - usage/config error (bad flags, missing/invalid config)
#   2 - ran successfully, but at least one secret is expired

setup() {
  source "$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
  fixtures="$BATS_TEST_DIRNAME/../fixtures"
}

@test "main prints JSON report and returns 2 when expired secrets are present" {
  run main --config "$fixtures/secrets-mixed.json" --today 2026-06-15 --warning-days 14 --format json
  [ "$status" -eq 2 ]
  [ "$(jq -r '.summary.expired' <<<"$output")" = "2" ]
}

@test "main returns 0 when --no-fail-on-expired is set despite expired secrets" {
  run main --config "$fixtures/secrets-mixed.json" --today 2026-06-15 --warning-days 14 --format json --no-fail-on-expired
  [ "$status" -eq 0 ]
}

@test "main returns 0 when no secrets are expired" {
  run main --config "$fixtures/secrets-all-ok.json" --today 2026-06-15 --warning-days 14 --format json
  [ "$status" -eq 0 ]
}

@test "main defaults to markdown format" {
  run main --config "$fixtures/secrets-all-ok.json" --today 2026-06-15
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Secret Rotation Report"* ]]
}

@test "main defaults warning-days to 14" {
  run main --config "$fixtures/secrets-mixed.json" --today 2026-06-15 --format json --no-fail-on-expired
  [ "$status" -eq 0 ]
  [ "$(jq -r '.warning_window_days' <<<"$output")" = "14" ]
}

@test "main writes the report to --output instead of stdout" {
  local out_file="$BATS_TEST_TMPDIR/report.json"
  run main --config "$fixtures/secrets-all-ok.json" --today 2026-06-15 --format json --output "$out_file"
  [ "$status" -eq 0 ]
  [ -f "$out_file" ]
  [ "$(jq -r '.summary.total' "$out_file")" = "2" ]
  [ -z "$output" ]
}

@test "main fails with exit 1 when --config is missing" {
  run main --today 2026-06-15
  [ "$status" -eq 1 ]
  [[ "$output" == *"--config"* ]]
}

@test "main fails with exit 1 when the config file does not exist" {
  run main --config "$fixtures/does-not-exist.json" --today 2026-06-15
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "main fails with exit 1 on an invalid --format" {
  run main --config "$fixtures/secrets-all-ok.json" --today 2026-06-15 --format yaml
  [ "$status" -eq 1 ]
  [[ "$output" == *"format"* ]]
}

@test "main fails with exit 1 on a non-numeric --warning-days" {
  run main --config "$fixtures/secrets-all-ok.json" --today 2026-06-15 --warning-days abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"warning-days"* ]]
}

@test "main fails with exit 1 on an unknown option" {
  run main --config "$fixtures/secrets-all-ok.json" --bogus-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "main --help prints usage and returns 0" {
  run main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "main propagates a config validation error with exit 1" {
  run main --config "$fixtures/secrets-missing-field.json" --today 2026-06-15
  [ "$status" -eq 1 ]
  [[ "$output" == *"INCOMPLETE_SECRET"* ]]
}
