#!/usr/bin/env bats
#
# Unit tests for the secret classification logic.
#
# These tests source the validator script and exercise its pure functions
# directly. The script guards its CLI entrypoint behind a sourced-vs-executed
# check so it can be loaded into the test process without running main().

setup() {
  # Absolute path to the script under test, resolved from this test file.
  SCRIPT="${BATS_TEST_DIRNAME}/../secret-rotation-validator.sh"
  # Source the script to import its functions for unit testing.
  source "$SCRIPT"
}

@test "classify_secret: expired when age >= policy" {
  # last_rotated 40 days before 'now', policy 30 days, warning window 7 days.
  run classify_secret "2024-01-01" 30 7 "2024-02-10"
  [ "$status" -eq 0 ]
  [ "$output" = "expired" ]
}

@test "classify_secret: warning when within the warning window" {
  # 26 days old, policy 30, warning 7 => 4 days left => warning.
  run classify_secret "2024-01-01" 30 7 "2024-01-27"
  [ "$status" -eq 0 ]
  [ "$output" = "warning" ]
}

@test "classify_secret: ok when well within policy" {
  # 5 days old, policy 30, warning 7 => 25 days left => ok.
  run classify_secret "2024-01-01" 30 7 "2024-01-06"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "classify_secret: boundary - exactly at policy is expired" {
  run classify_secret "2024-01-01" 30 7 "2024-01-31"
  [ "$status" -eq 0 ]
  [ "$output" = "expired" ]
}

@test "classify_secret: boundary - exactly at warning threshold is warning" {
  # policy 30, warning 7 => threshold at 23 days old.
  run classify_secret "2024-01-01" 30 7 "2024-01-24"
  [ "$status" -eq 0 ]
  [ "$output" = "warning" ]
}
