#!/usr/bin/env bats
# Tests for manifest parsing functions (package.json / requirements.txt).

setup() {
  load 'test_helper.bash'
  LIB="${BATS_TEST_DIRNAME}/../lib/license_checker.sh"
  source "$LIB"
  FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"
}

@test "parse_package_json extracts name and version pairs from dependencies" {
  run parse_package_json "${FIXTURES}/package.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'left-pad\t1.3.0'* ]]
  [[ "$output" == *$'lodash\t4.17.21'* ]]
}

@test "parse_package_json fails gracefully on missing file" {
  run parse_package_json "${FIXTURES}/does-not-exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse_requirements_txt extracts name and version pairs" {
  run parse_requirements_txt "${FIXTURES}/requirements.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'requests\t2.31.0'* ]]
  [[ "$output" == *$'flask\t2.3.2'* ]]
}

@test "parse_requirements_txt fails gracefully on missing file" {
  run parse_requirements_txt "${FIXTURES}/does-not-exist.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
