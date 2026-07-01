#!/usr/bin/env bats
# Static analysis gate: every shell script we ship must pass `bash -n`
# (syntax) and `shellcheck` (lint) on the host. This is NOT a functional
# test of aggregate-results.sh's behavior (that only happens through the
# GitHub Actions pipeline via act, per project policy) -- it's a style/
# syntax gate that any real bash project runs regardless of how the code
# is functionally exercised.

setup() {
  cd "${BATS_TEST_DIRNAME}/.." || exit 1
  # Collect the list of shell scripts under test once per test.
  mapfile -t SCRIPTS < <(find . -name '*.sh' -not -path './.git/*' | sort)
}

@test "at least one shell script exists" {
  [ "${#SCRIPTS[@]}" -gt 0 ]
}

@test "all shell scripts pass bash -n syntax check" {
  for f in "${SCRIPTS[@]}"; do
    run bash -n "$f"
    [ "$status" -eq 0 ] || {
      echo "syntax error in $f: $output"
      return 1
    }
  done
}

@test "all shell scripts pass shellcheck" {
  for f in "${SCRIPTS[@]}"; do
    run shellcheck "$f"
    [ "$status" -eq 0 ] || {
      echo "shellcheck failed for $f: $output"
      return 1
    }
  done
}
