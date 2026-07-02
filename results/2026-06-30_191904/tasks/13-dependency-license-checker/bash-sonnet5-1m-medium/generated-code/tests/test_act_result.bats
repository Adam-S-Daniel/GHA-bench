#!/usr/bin/env bats
# Asserts on the recorded output of the act-driven pipeline runs (see
# tests/run_act_scenarios.sh, which produces act-result.txt). This is the
# "did the real GitHub Actions pipeline behave correctly" check: exact
# values, not just "some output appeared".

setup() {
  RESULT_FILE="${BATS_TEST_DIRNAME}/../act-result.txt"
}

@test "act-result.txt exists" {
  [ -f "$RESULT_FILE" ]
}

@test "clean-package-json scenario: both jobs exited 0 and both jobs succeeded" {
  local block
  block="$(awk '/TEST CASE: clean-package-json/,/END TEST CASE: clean-package-json/' "$RESULT_FILE")"
  [[ "$block" == *"EXIT_CODE: 0"* ]]
  [[ "$(echo "$block" | grep -c 'Job succeeded')" -eq 2 ]]
}

@test "clean-package-json scenario: report shows exact approved/denied/unknown counts" {
  local block
  block="$(awk '/TEST CASE: clean-package-json/,/END TEST CASE: clean-package-json/' "$RESULT_FILE")"
  [[ "$block" == *"Approved: 4"* ]]
  [[ "$block" == *"Denied: 0"* ]]
  [[ "$block" == *"Unknown: 0"* ]]
  [[ "$block" == *"lodash"*"4.17.21"*"MIT"*"approved"* ]]
}

@test "unknown-dependency scenario: both jobs exited 0 and both jobs succeeded" {
  local block
  block="$(awk '/TEST CASE: unknown-dependency/,/END TEST CASE: unknown-dependency/' "$RESULT_FILE")"
  [[ "$block" == *"EXIT_CODE: 0"* ]]
  [[ "$(echo "$block" | grep -c 'Job succeeded')" -eq 2 ]]
}

@test "unknown-dependency scenario: report shows exact approved/denied/unknown counts" {
  local block
  block="$(awk '/TEST CASE: unknown-dependency/,/END TEST CASE: unknown-dependency/' "$RESULT_FILE")"
  [[ "$block" == *"Approved: 1"* ]]
  [[ "$block" == *"Denied: 0"* ]]
  [[ "$block" == *"Unknown: 1"* ]]
  [[ "$block" == *"totally-unheard-of-pkg"*"1.0.0"*"UNKNOWN"*"unknown"* ]]
}
