#!/usr/bin/env bats
# Tests for the (mockable) license lookup function.
# lookup_license reads from LICENSE_DB_FILE (JSON: name/name@version -> license)
# instead of hitting a real registry, so it is fully deterministic in tests.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../lib/license_checker.sh"
  source "$LIB"
  export LICENSE_DB_FILE="${BATS_TEST_DIRNAME}/../fixtures/license-db.json"
}

@test "lookup_license returns license for a known package by name" {
  run lookup_license "lodash" "4.17.21"
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup_license prefers exact name@version match over name-only match" {
  run lookup_license "left-pad" "1.3.0"
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup_license returns UNKNOWN for a package not in the db" {
  run lookup_license "totally-unheard-of-pkg" "0.0.1"
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

@test "lookup_license errors when LICENSE_DB_FILE is missing" {
  export LICENSE_DB_FILE="${BATS_TEST_DIRNAME}/../fixtures/no-such-db.json"
  run lookup_license "lodash" "4.17.21"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
