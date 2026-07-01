#!/usr/bin/env bats
# Unit tests for date-handling helper functions in secret-rotation-validator.sh.
# These functions are sourced directly (no subprocess) so we can assert on
# their return values precisely.

setup() {
  # SUT = "system under test". Source the script without triggering main(),
  # since main() is only invoked when the file is executed directly (see the
  # BASH_SOURCE guard at the bottom of the script).
  load_path="$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
  source "$load_path"
}

@test "days_between computes whole days between two ISO dates" {
  run days_between "2026-01-01" "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$output" -eq 165 ]
}

@test "days_between returns 0 for the same date" {
  run days_between "2026-06-15" "2026-06-15"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

@test "days_between returns a negative number when second date precedes first" {
  run days_between "2026-06-15" "2026-06-01"
  [ "$status" -eq 0 ]
  [ "$output" -eq -14 ]
}

@test "days_between fails on an unparseable date" {
  run days_between "not-a-date" "2026-06-15"
  [ "$status" -ne 0 ]
}

@test "is_valid_date accepts a well-formed calendar date" {
  run is_valid_date "2026-06-15"
  [ "$status" -eq 0 ]
}

@test "is_valid_date rejects a malformed date string" {
  run is_valid_date "06/15/2026"
  [ "$status" -ne 0 ]
}

@test "is_valid_date rejects a calendar date that does not exist" {
  run is_valid_date "2026-02-30"
  [ "$status" -ne 0 ]
}
