#!/usr/bin/env bats
# Tests for bump-version.sh, developed with red/green TDD.
# The script is sourceable (function definitions only when sourced), which
# lets us unit-test each function in isolation before testing end-to-end.

# run --separate-stderr (used by the e2e tests) needs bats >= 1.5.0.
bats_require_minimum_version 1.5.0

setup() {
  # Directory of this test file, so tests work from any CWD.
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_DIR="$(dirname "$TEST_DIR")"
  SCRIPT="$PROJECT_DIR/bump-version.sh"
  FIXTURES="$TEST_DIR/fixtures"
  # Isolated scratch dir per test.
  WORK="$(mktemp -d)"
  # shellcheck disable=SC1090  # sourced path is computed at runtime
  source "$SCRIPT"
}

teardown() {
  rm -rf "$WORK"
}

# --- read_version -----------------------------------------------------------

@test "read_version reads a plain VERSION file" {
  echo "1.2.3" > "$WORK/VERSION"
  run read_version "$WORK/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "read_version extracts version from package.json" {
  cp "$FIXTURES/package.json" "$WORK/package.json"
  run read_version "$WORK/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
}

@test "read_version fails with a clear error on a missing file" {
  run read_version "$WORK/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "read_version fails with a clear error on an invalid semver" {
  echo "banana" > "$WORK/VERSION"
  run read_version "$WORK/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid semantic version"* ]]
}

# --- determine_bump ---------------------------------------------------------

@test "determine_bump: feat commit yields minor" {
  run determine_bump "$FIXTURES/commits-feat.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "minor" ]
}

@test "determine_bump: fix commit yields patch" {
  run determine_bump "$FIXTURES/commits-fix.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "patch" ]
}

@test "determine_bump: 'feat!:' marker yields major" {
  run determine_bump "$FIXTURES/commits-breaking.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "major" ]
}

@test "determine_bump: BREAKING CHANGE footer yields major" {
  run determine_bump "$FIXTURES/commits-breaking-footer.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "major" ]
}

@test "determine_bump: mixed feat+fix yields minor (highest wins)" {
  run determine_bump "$FIXTURES/commits-mixed.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "minor" ]
}

@test "determine_bump: only chore/docs yields none" {
  run determine_bump "$FIXTURES/commits-none.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "determine_bump fails on a missing commit log" {
  run determine_bump "$WORK/nope.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# --- bump_version -----------------------------------------------------------

@test "bump_version major resets minor and patch" {
  run bump_version "1.2.3" major
  [ "$output" = "2.0.0" ]
}

@test "bump_version minor resets patch" {
  run bump_version "1.2.3" minor
  [ "$output" = "1.3.0" ]
}

@test "bump_version patch increments patch only" {
  run bump_version "1.2.3" patch
  [ "$output" = "1.2.4" ]
}

@test "bump_version rejects an unknown bump type" {
  run bump_version "1.2.3" banana
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown bump type"* ]]
}

# --- write_version ----------------------------------------------------------

@test "write_version rewrites a plain VERSION file" {
  echo "1.2.3" > "$WORK/VERSION"
  write_version "$WORK/VERSION" "1.3.0"
  [ "$(cat "$WORK/VERSION")" = "1.3.0" ]
}

@test "write_version updates only the version field in package.json" {
  cp "$FIXTURES/package.json" "$WORK/package.json"
  write_version "$WORK/package.json" "2.0.0"
  grep -q '"version": "2.0.0"' "$WORK/package.json"
  grep -q '"name": "demo-app"' "$WORK/package.json" # rest of file intact
}

# --- generate_changelog -----------------------------------------------------

@test "generate_changelog groups commits under typed sections" {
  generate_changelog "1.2.0" "$FIXTURES/commits-mixed.txt" "$WORK/CHANGELOG.md"
  run cat "$WORK/CHANGELOG.md"
  [[ "$output" == *"## 1.2.0"* ]]
  [[ "$output" == *"### Features"* ]]
  [[ "$output" == *"add pagination support"* ]]
  [[ "$output" == *"add dark mode"* ]]
  [[ "$output" == *"### Fixes"* ]]
  [[ "$output" == *"align buttons on mobile"* ]]
}

@test "generate_changelog prepends the new entry above existing ones" {
  printf '# Changelog\n\n## 1.1.0 - old\n' > "$WORK/CHANGELOG.md"
  generate_changelog "1.2.0" "$FIXTURES/commits-feat.txt" "$WORK/CHANGELOG.md"
  run cat "$WORK/CHANGELOG.md"
  [[ "$output" == *"## 1.2.0"* ]]
  [[ "$output" == *"## 1.1.0 - old"* ]]
  # New entry must appear before the old one.
  local new_line old_line
  new_line="$(grep -n '## 1.2.0' "$WORK/CHANGELOG.md" | cut -d: -f1)"
  old_line="$(grep -n '## 1.1.0' "$WORK/CHANGELOG.md" | cut -d: -f1)"
  [ "$new_line" -lt "$old_line" ]
}

@test "generate_changelog includes a Breaking Changes section" {
  generate_changelog "2.0.0" "$FIXTURES/commits-breaking.txt" "$WORK/CHANGELOG.md"
  run cat "$WORK/CHANGELOG.md"
  [[ "$output" == *"### Breaking Changes"* ]]
  [[ "$output" == *"drop support for Node 14"* ]]
}

# --- end-to-end CLI ---------------------------------------------------------

@test "e2e: feat commits bump 1.1.0 -> 1.2.0 and update all files" {
  echo "1.1.0" > "$WORK/VERSION"
  run --separate-stderr "$SCRIPT" --version-file "$WORK/VERSION" \
    --commits-file "$FIXTURES/commits-feat.txt" \
    --changelog "$WORK/CHANGELOG.md"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.0" ]
  [ "$(cat "$WORK/VERSION")" = "1.2.0" ]
  grep -q '## 1.2.0' "$WORK/CHANGELOG.md"
}

@test "e2e: fix commits bump patch on package.json" {
  cp "$FIXTURES/package.json" "$WORK/package.json"
  run --separate-stderr "$SCRIPT" --version-file "$WORK/package.json" \
    --commits-file "$FIXTURES/commits-fix.txt" \
    --changelog "$WORK/CHANGELOG.md"
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.1" ]
  grep -q '"version": "1.1.1"' "$WORK/package.json"
}

@test "e2e: breaking commits bump major" {
  echo "1.1.0" > "$WORK/VERSION"
  run --separate-stderr "$SCRIPT" --version-file "$WORK/VERSION" \
    --commits-file "$FIXTURES/commits-breaking.txt" \
    --changelog "$WORK/CHANGELOG.md"
  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "e2e: no relevant commits keeps the version and says so" {
  echo "1.1.0" > "$WORK/VERSION"
  run --separate-stderr "$SCRIPT" --version-file "$WORK/VERSION" \
    --commits-file "$FIXTURES/commits-none.txt" \
    --changelog "$WORK/CHANGELOG.md"
  [ "$status" -eq 0 ]
  # stdout still prints the (unchanged) version; a notice goes to stderr.
  [ "$output" = "1.1.0" ]
  # shellcheck disable=SC2154  # $stderr is set by bats' run --separate-stderr
  [[ "$stderr" == *"no version bump needed"* ]]
  [ "$(cat "$WORK/VERSION")" = "1.1.0" ]
  [ ! -f "$WORK/CHANGELOG.md" ] # no changelog entry when nothing changed
}

@test "e2e: unknown flag produces a usage error" {
  run "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
