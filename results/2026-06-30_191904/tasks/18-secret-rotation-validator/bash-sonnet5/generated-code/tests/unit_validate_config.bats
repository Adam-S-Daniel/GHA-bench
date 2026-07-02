#!/usr/bin/env bats
# Unit tests for validate_config(): structural + field-level validation of
# the secrets config file, run before any date math happens.

setup() {
  source "$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
  fixtures="$BATS_TEST_DIRNAME/../fixtures"
}

@test "validate_config accepts a well-formed config" {
  run validate_config "$fixtures/secrets-mixed.json"
  [ "$status" -eq 0 ]
}

@test "validate_config accepts an empty array" {
  run validate_config "$fixtures/secrets-empty.json"
  [ "$status" -eq 0 ]
}

@test "validate_config rejects a missing file" {
  run validate_config "$fixtures/does-not-exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "validate_config rejects malformed JSON" {
  run validate_config "$fixtures/secrets-invalid.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "validate_config rejects a top-level object instead of an array" {
  run validate_config "$fixtures/secrets-not-array.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"array"* ]]
}

@test "validate_config rejects a secret missing a required field" {
  run validate_config "$fixtures/secrets-missing-field.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rotation_days"* ]]
  [[ "$output" == *"INCOMPLETE_SECRET"* ]]
}

@test "validate_config rejects a malformed last_rotated date" {
  run validate_config "$fixtures/secrets-bad-date.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BAD_DATE_SECRET"* ]]
}

@test "validate_config rejects a non-positive rotation_days" {
  run validate_config "$fixtures/secrets-bad-rotation.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ZERO_ROTATION"* ]]
}
