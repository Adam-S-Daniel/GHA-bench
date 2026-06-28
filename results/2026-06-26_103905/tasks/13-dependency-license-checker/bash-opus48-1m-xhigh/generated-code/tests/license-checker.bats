#!/usr/bin/env bats
#
# Unit tests for license-checker.sh (bats-core).
#
# The script is written so that sourcing it does NOT execute main() (guarded by
# a `BASH_SOURCE == $0` check at the bottom). That lets these tests source the
# script once and exercise its functions directly, in classic TDD fashion.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../license-checker.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

# --- manifest type detection ------------------------------------------------

@test "detect_manifest_type identifies an npm package.json" {
  run detect_manifest_type "$FIXTURES/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "npm" ]
}

@test "detect_manifest_type identifies a pip requirements.txt" {
  run detect_manifest_type "$FIXTURES/requirements.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

# --- manifest parsing (npm) -------------------------------------------------

@test "parse_manifest extracts name<TAB>version pairs from package.json" {
  run parse_manifest "$FIXTURES/package.json" npm
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  # Version ranges (^, ~) are normalised down to a bare semver.
  [ "${lines[0]}" = $'express\t4.18.2' ]
  [ "${lines[1]}" = $'lodash\t4.17.21' ]
  [ "${lines[2]}" = $'jest\t29.7.0' ]
}

# --- manifest parsing (pip) -------------------------------------------------

@test "parse_manifest extracts name<TAB>version pairs from requirements.txt" {
  run parse_manifest "$FIXTURES/requirements.txt" pip
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = $'flask\t2.3.3' ]
  [ "${lines[1]}" = $'requests\t2.31.0' ]
  # A dependency with no pinned version becomes "unspecified".
  [ "${lines[2]}" = $'numpy\tunspecified' ]
}

# --- config loading + license classification --------------------------------

@test "classify_license: allow-listed license is APPROVED" {
  load_config "$FIXTURES/licenses.config"
  run classify_license MIT
  [ "$status" -eq 0 ]
  [ "$output" = "APPROVED" ]
}

@test "classify_license: deny-listed license is DENIED" {
  load_config "$FIXTURES/licenses.config"
  run classify_license GPL-3.0
  [ "$output" = "DENIED" ]
}

@test "classify_license: unrecognised license is UNKNOWN" {
  load_config "$FIXTURES/licenses.config"
  run classify_license "Weird-Proprietary-1.0"
  [ "$output" = "UNKNOWN" ]
}

@test "classify_license: the literal UNKNOWN sentinel stays UNKNOWN" {
  load_config "$FIXTURES/licenses.config"
  run classify_license UNKNOWN
  [ "$output" = "UNKNOWN" ]
}

@test "classify_license: deny-list takes precedence over allow-list" {
  load_config "$FIXTURES/licenses.config"
  ALLOW["GPL-3.0"]=1   # create an artificial allow/deny conflict
  run classify_license GPL-3.0
  [ "$output" = "DENIED" ]
}

@test "load_config fails clearly on a missing config file" {
  run load_config "$FIXTURES/does-not-exist.config"
  [ "$status" -ne 0 ]
  [[ "$output" == *"config not found"* ]]
}

# --- mock license lookup ----------------------------------------------------

@test "lookup_license: exact name@version match from mock DB" {
  load_db "$FIXTURES/license-db.tsv"
  run lookup_license express 4.18.2
  [ "$status" -eq 0 ]
  [ "$output" = "MIT" ]
}

@test "lookup_license: wildcard version match from mock DB" {
  load_db "$FIXTURES/license-db.tsv"
  run lookup_license lodash 4.17.21
  [ "$output" = "MIT" ]
}

@test "lookup_license: unknown dependency yields UNKNOWN" {
  load_db "$FIXTURES/license-db.tsv"
  run lookup_license mystery-lib 9.9.9
  [ "$output" = "UNKNOWN" ]
}

@test "lookup_license: honours the LICENSE_LOOKUP_CMD override" {
  LICENSE_LOOKUP_CMD="$BATS_TEST_DIRNAME/mocks/mock-lookup.sh" run lookup_license bad-lib 1.0.0
  [ "$status" -eq 0 ]
  [ "$output" = "GPL-3.0" ]
}

@test "lookup_license: LICENSE_LOOKUP_CMD empty result yields UNKNOWN" {
  LICENSE_LOOKUP_CMD="$BATS_TEST_DIRNAME/mocks/mock-lookup.sh" run lookup_license mystery-lib 1.0.0
  [ "$output" = "UNKNOWN" ]
}

@test "load_db fails clearly on a missing database file" {
  run load_db "$FIXTURES/nope.tsv"
  [ "$status" -ne 0 ]
  [[ "$output" == *"license db not found"* ]]
}

# --- end-to-end report (text) -----------------------------------------------

@test "report: all-approved manifest is COMPLIANT and exits 0" {
  run "$SCRIPT" --manifest "$FIXTURES/package.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary: 3 total, 3 approved, 0 denied, 0 unknown"* ]]
  [[ "$output" == *"Result: COMPLIANT"* ]]
  # Each dependency row shows name, version, license and APPROVED status.
  echo "$output" | grep -Eq "express[[:space:]]+4\.18\.2[[:space:]]+MIT[[:space:]]+APPROVED"
}

@test "report: a denied license makes the report NON-COMPLIANT and exits 1" {
  run "$SCRIPT" --manifest "$FIXTURES/package-denied.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Summary: 2 total, 1 approved, 1 denied, 0 unknown"* ]]
  [[ "$output" == *"Result: NON-COMPLIANT"* ]]
  echo "$output" | grep -Eq "bad-lib[[:space:]]+1\.0\.0[[:space:]]+GPL-3\.0[[:space:]]+DENIED"
}

@test "report: an unknown license makes the report NON-COMPLIANT and exits 2" {
  run "$SCRIPT" --manifest "$FIXTURES/package-unknown.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Summary: 2 total, 1 approved, 0 denied, 1 unknown"* ]]
  [[ "$output" == *"Result: NON-COMPLIANT"* ]]
  echo "$output" | grep -Eq "mystery-lib[[:space:]]+2\.0\.0[[:space:]]+UNKNOWN[[:space:]]+UNKNOWN"
}

@test "report: --no-fail always exits 0 even when non-compliant" {
  run "$SCRIPT" --manifest "$FIXTURES/package-denied.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv" --no-fail
  [ "$status" -eq 0 ]
  [[ "$output" == *"Result: NON-COMPLIANT"* ]]
}

@test "report: works against a pip requirements.txt manifest" {
  run "$SCRIPT" --manifest "$FIXTURES/requirements.txt" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary: 3 total, 3 approved, 0 denied, 0 unknown"* ]]
  echo "$output" | grep -Eq "flask[[:space:]]+2\.3\.3[[:space:]]+BSD-3-Clause[[:space:]]+APPROVED"
}

# --- end-to-end report (json) -----------------------------------------------

@test "report: --format json emits valid, correct JSON" {
  run "$SCRIPT" --manifest "$FIXTURES/package-denied.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv" --format json --no-fail
  [ "$status" -eq 0 ]
  # Valid JSON parseable by jq, with the expected summary values.
  echo "$output" | jq -e '.summary.total == 2' >/dev/null
  echo "$output" | jq -e '.summary.denied == 1' >/dev/null
  echo "$output" | jq -e '.summary.compliant == false' >/dev/null
  echo "$output" | jq -e '.dependencies[] | select(.name=="bad-lib") | .status == "denied"' >/dev/null
}

# --- argument / error handling ----------------------------------------------

@test "errors: missing --manifest argument fails with a usage message" {
  run "$SCRIPT" --config "$FIXTURES/licenses.config" --db "$FIXTURES/license-db.tsv"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--manifest is required"* ]]
}

@test "errors: a nonexistent manifest fails gracefully" {
  run "$SCRIPT" --manifest "$FIXTURES/nope.json" \
                --config "$FIXTURES/licenses.config" \
                --db "$FIXTURES/license-db.tsv"
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest not found"* ]]
}

@test "errors: an unknown flag is rejected with a clear message" {
  run "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "help: --help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
