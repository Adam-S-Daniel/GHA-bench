#!/usr/bin/env bats
#
# Unit tests for bump-version.sh (TDD red/green).
#
# These tests exercise the script's pure logic in isolation: version parsing,
# bump-type detection from conventional commits, file updates and changelog
# generation. The end-to-end pipeline test that runs everything through the
# GitHub Actions workflow with `act` lives in tests/act-harness.bats.

setup() {
  # Resolve repo root (one level up from this tests/ dir) and the script path.
  TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  REPO_ROOT="$( cd "$TEST_DIR/.." >/dev/null 2>&1 && pwd )"
  SCRIPT="$REPO_ROOT/bump-version.sh"

  # Each test runs in its own throwaway working directory.
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
}

teardown() {
  [ -n "$WORK" ] && rm -rf "$WORK"
}

@test "prints usage and exits non-zero when no arguments are given" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "reads a plain version file and bumps minor on a feat commit" {
  echo "1.1.0" > VERSION
  printf 'feat: add new login page\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  # The new version is the last line of stdout.
  [[ "$output" == *"1.2.0"* ]]
  # The version file is updated in place.
  [ "$(cat VERSION)" = "1.2.0" ]
}

@test "bumps patch on a fix commit" {
  echo "1.1.0" > VERSION
  printf 'fix: correct off-by-one error\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "1.1.1" ]
}

@test "bumps major on a breaking change (feat!)" {
  echo "1.1.0" > VERSION
  printf 'feat!: drop support for node 14\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "2.0.0" ]
}

@test "bumps major on a BREAKING CHANGE footer" {
  echo "0.4.2" > VERSION
  printf 'feat: new api\n\nBREAKING CHANGE: removed old endpoint\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "1.0.0" ]
}

@test "highest-precedence bump wins (feat + fix + breaking => major)" {
  echo "2.3.4" > VERSION
  printf 'fix: a\nfeat: b\nfix!: c\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "3.0.0" ]
}

@test "feat takes precedence over fix => minor" {
  echo "2.3.4" > VERSION
  printf 'fix: a\nfeat: b\nfix: c\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "2.4.0" ]
}

@test "parses and updates a package.json version field" {
  printf '{\n  "name": "demo",\n  "version": "1.0.0",\n  "private": true\n}\n' > package.json
  printf 'fix: patch a bug\n' > commits.txt
  run "$SCRIPT" --package-json package.json --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION 2>/dev/null)" != "1.0.1" ]  # VERSION file should not be created
  grep -q '"version": "1.0.1"' package.json
}

@test "honours a leading v in the version string and preserves it" {
  echo "v1.2.3" > VERSION
  printf 'feat: thing\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -eq 0 ]
  [ "$(cat VERSION)" = "v1.3.0" ]
}

@test "generates a changelog entry grouped by type" {
  echo "1.0.0" > VERSION
  printf 'feat: add widget\nfix: repair gadget\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt --changelog CHANGELOG.md
  [ "$status" -eq 0 ]
  [ -f CHANGELOG.md ]
  grep -q "## 1.1.0" CHANGELOG.md
  grep -q "Features" CHANGELOG.md
  grep -q "add widget" CHANGELOG.md
  grep -q "Bug Fixes" CHANGELOG.md
  grep -q "repair gadget" CHANGELOG.md
}

@test "errors clearly when there are no conventional commits" {
  echo "1.0.0" > VERSION
  printf 'chore: tidy up\ndocs: update readme\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"no version bump"* ]]
  # The version file must be left untouched.
  [ "$(cat VERSION)" = "1.0.0" ]
}

@test "errors when the version file does not exist" {
  printf 'feat: x\n' > commits.txt
  run "$SCRIPT" --version-file does-not-exist --commits commits.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"No such"* ]]
}

@test "errors when the version string is malformed" {
  echo "not-a-version" > VERSION
  printf 'feat: x\n' > commits.txt
  run "$SCRIPT" --version-file VERSION --commits commits.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"malformed"* ]]
}
