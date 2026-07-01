#!/usr/bin/env bats
# Tests for the (mockable) license lookup and allow/deny classification.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$DIR/lib/license_lookup.sh"
  export LICENSE_DB_FILE="$DIR/test/fixtures/license-db.json"
}

@test "lookup_license returns the mocked license for a known package" {
  run lookup_license "left-pad"
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup_license returns UNKNOWN for a package not in the mock db" {
  run lookup_license "mystery-pkg"
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

@test "lookup_license errors meaningfully when LICENSE_DB_FILE is missing" {
  export LICENSE_DB_FILE="/no/such/db.json"
  run lookup_license "left-pad"
  [ "$status" -ne 0 ]
  [[ "$output" == *"license database not found"* ]]
}

@test "classify_license returns approved for an allow-listed license" {
  run classify_license "MIT" "$DIR/test/fixtures/license-config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "approved" ]
}

@test "classify_license returns denied for a deny-listed license" {
  run classify_license "GPL-3.0" "$DIR/test/fixtures/license-config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "denied" ]
}

@test "classify_license returns unknown for a license in neither list" {
  run classify_license "UNKNOWN" "$DIR/test/fixtures/license-config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}
