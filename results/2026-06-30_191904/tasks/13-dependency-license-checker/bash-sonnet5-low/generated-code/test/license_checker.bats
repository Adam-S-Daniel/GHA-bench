#!/usr/bin/env bats
# End-to-end tests for the license_checker.sh CLI.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$DIR/license_checker.sh"
  FIXTURES="$DIR/test/fixtures"
}

@test "license_checker.sh generates a report for package.json" {
  run "$SCRIPT" --manifest "$FIXTURES/package.json" --config "$FIXTURES/license-config.json" --license-db "$FIXTURES/license-db.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"left-pad,1.3.0,MIT,approved"* ]]
  [[ "$output" == *"gpl-lib,2.0.0,GPL-3.0,denied"* ]]
  [[ "$output" == *"mystery-pkg,0.1.0,UNKNOWN,unknown"* ]]
}

@test "license_checker.sh generates a report for requirements.txt" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" --config "$FIXTURES/license-config.json" --license-db "$FIXTURES/license-db.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requests,2.31.0,Apache-2.0,approved"* ]]
  [[ "$output" == *"flask,>=2.0.0,BSD-3-Clause,approved"* ]]
  [[ "$output" == *"mystery-pkg,0.1.0,UNKNOWN,unknown"* ]]
}

@test "license_checker.sh exits with code 2 when any dependency is denied" {
  run "$SCRIPT" --manifest "$FIXTURES/package.json" --config "$FIXTURES/license-config.json" --license-db "$FIXTURES/license-db.json"
  [ "$status" -eq 2 ]
}

@test "license_checker.sh exits 0 when nothing is denied" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" --config "$FIXTURES/license-config.json" --license-db "$FIXTURES/license-db.json"
  [ "$status" -eq 0 ]
}

@test "license_checker.sh errors with a meaningful message on missing manifest" {
  run "$SCRIPT" --manifest "$FIXTURES/does-not-exist.json" --config "$FIXTURES/license-config.json" --license-db "$FIXTURES/license-db.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "license_checker.sh errors when required arguments are missing" {
  run "$SCRIPT" --manifest "$FIXTURES/package.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"required"* ]]
}
