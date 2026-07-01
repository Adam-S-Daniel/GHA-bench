#!/usr/bin/env bats
# Tests for classify_license: decides approved/denied/unknown status for a
# license string against the allow-list/deny-list config.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../lib/license_checker.sh"
  source "$LIB"
  export LICENSE_CONFIG_FILE="${BATS_TEST_DIRNAME}/../fixtures/license-config.json"
}

@test "classify_license returns approved for an allow-listed license" {
  run classify_license "MIT"
  [ "$status" -eq 0 ]
  [ "$output" = "approved" ]
}

@test "classify_license returns denied for a deny-listed license" {
  run classify_license "GPL-3.0"
  [ "$status" -eq 0 ]
  [ "$output" = "denied" ]
}

@test "classify_license returns unknown for a license in neither list" {
  run classify_license "MPL-2.0"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "classify_license returns unknown for UNKNOWN license string" {
  run classify_license "UNKNOWN"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "classify_license errors when config file is missing" {
  export LICENSE_CONFIG_FILE="${BATS_TEST_DIRNAME}/../fixtures/no-such-config.json"
  run classify_license "MIT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
