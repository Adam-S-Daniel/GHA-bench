#!/usr/bin/env bats
# TDD test suite for license_checker.sh (red/green cycles).
#
# Cycle 1 (this test): parsing a requirements.txt manifest into
# "name version" lines. Written BEFORE any implementation exists,
# so it must fail first (red), then we implement (green).

setup() {
  # Directory of this test file, so tests work from any CWD.
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(dirname "$TEST_DIR")"
  CHECKER="$PROJECT_DIR/license_checker.sh"
  FIXTURES="$TEST_DIR/fixtures"
}

# --- Cycle 1: parse requirements.txt ---------------------------------------

@test "parse: extracts name and version from requirements.txt" {
  run "$CHECKER" parse "$FIXTURES/requirements.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "requests 2.31.0" ]
  [ "${lines[1]}" = "flask 3.0.2" ]
  [ "${lines[2]}" = "left-pad 1.3.0" ]
}

# --- Cycle 2: parse package.json --------------------------------------------

@test "parse: extracts dependencies and devDependencies from package.json" {
  run "$CHECKER" parse "$FIXTURES/package.json"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "left-pad 1.3.0" ]
  [ "${lines[1]}" = "evil-lib 2.0.0" ]
  [ "${lines[2]}" = "mystery-pkg 0.1.0" ]
}

@test "parse: fails with meaningful error for missing manifest" {
  run "$CHECKER" parse "$FIXTURES/does-not-exist.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest not found"* ]]
}

# --- Cycle 3: license lookup (mocked DB) and classification -----------------

@test "lookup: returns license from mock database" {
  run "$CHECKER" lookup left-pad "$FIXTURES/licenses.db"
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup: returns UNKNOWN for dependency not in database" {
  run "$CHECKER" lookup mystery-pkg "$FIXTURES/licenses.db"
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

@test "classify: allow-listed license is approved" {
  run "$CHECKER" classify MIT "$FIXTURES/policy.conf"
  [ "$output" = "approved" ]
}

@test "classify: deny-listed license is denied" {
  run "$CHECKER" classify GPL-3.0 "$FIXTURES/policy.conf"
  [ "$output" = "denied" ]
}

@test "classify: unlisted license is unknown" {
  run "$CHECKER" classify WTFPL "$FIXTURES/policy.conf"
  [ "$output" = "unknown" ]
}

# --- Cycle 4: end-to-end compliance report ----------------------------------

@test "report: lists each dependency with license and status" {
  run "$CHECKER" report "$FIXTURES/package.json" "$FIXTURES/policy.conf" "$FIXTURES/licenses.db"
  [ "$status" -eq 0 ]
  [[ "$output" == *"left-pad 1.3.0 MIT approved"* ]]
  [[ "$output" == *"evil-lib 2.0.0 GPL-3.0 denied"* ]]
  [[ "$output" == *"mystery-pkg 0.1.0 UNKNOWN unknown"* ]]
}

@test "report: includes summary counts" {
  run "$CHECKER" report "$FIXTURES/package.json" "$FIXTURES/policy.conf" "$FIXTURES/licenses.db"
  [[ "$output" == *"SUMMARY: total=3 approved=1 denied=1 unknown=1"* ]]
}

@test "report: fully approved requirements.txt manifest" {
  run "$CHECKER" report "$FIXTURES/requirements.txt" "$FIXTURES/policy.conf" "$FIXTURES/licenses.db"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requests 2.31.0 Apache-2.0 approved"* ]]
  [[ "$output" == *"SUMMARY: total=3 approved=3 denied=0 unknown=0"* ]]
}

@test "report: --strict exits non-zero when a denied license is present" {
  run "$CHECKER" report --strict "$FIXTURES/package.json" "$FIXTURES/policy.conf" "$FIXTURES/licenses.db"
  [ "$status" -eq 2 ]
  [[ "$output" == *"denied=1"* ]]
}

@test "unknown command produces a meaningful error" {
  run "$CHECKER" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}
