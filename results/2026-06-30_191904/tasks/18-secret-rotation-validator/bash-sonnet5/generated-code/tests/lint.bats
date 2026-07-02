#!/usr/bin/env bats
# Static analysis checks for the implementation script itself.

setup() {
  script="$BATS_TEST_DIRNAME/../secret-rotation-validator.sh"
}

@test "secret-rotation-validator.sh passes bash -n syntax check" {
  run bash -n "$script"
  [ "$status" -eq 0 ]
}

@test "secret-rotation-validator.sh passes shellcheck with no warnings" {
  run shellcheck "$script"
  [ "$status" -eq 0 ]
}
