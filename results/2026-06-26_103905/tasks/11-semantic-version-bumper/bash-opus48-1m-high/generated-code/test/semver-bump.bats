#!/usr/bin/env bats
#
# Unit tests for semver-bump.sh, developed red/green via TDD.
#
# The script is written so that sourcing it does NOT run main() (it guards on
# BASH_SOURCE == $0). That lets these tests call individual functions directly.

setup() {
  # Absolute path to the script under test (one dir up from this test file).
  SCRIPT="${BATS_TEST_DIRNAME}/../semver-bump.sh"
  # Per-test scratch directory so tests never touch each other's files.
  TMP="$(mktemp -d)"
  # Source the script to expose its functions without executing main().
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

teardown() {
  rm -rf "$TMP"
}

# --- parse_version --------------------------------------------------------

@test "parse_version reads a plain VERSION file" {
  printf '1.2.3\n' > "$TMP/VERSION"
  run parse_version "$TMP/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "parse_version reads the version field from package.json" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "0.3.4",
  "scripts": { "test": "bats" }
}
JSON
  run parse_version "$TMP/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0.3.4" ]
}

@test "parse_version fails with a clear message on a missing file" {
  run parse_version "$TMP/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version file not found"* ]]
}

# --- validate_version -----------------------------------------------------

@test "validate_version accepts a well-formed semver" {
  run validate_version "10.20.30"
  [ "$status" -eq 0 ]
}

@test "validate_version rejects a malformed version" {
  run validate_version "1.2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

# --- determine_bump -------------------------------------------------------

@test "determine_bump returns patch for a fix commit" {
  printf 'fix: correct an off-by-one error\n' > "$TMP/commits.txt"
  run determine_bump "$TMP/commits.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "patch" ]
}

@test "determine_bump returns minor for a feat commit" {
  printf 'feat: add a shiny new flag\n' > "$TMP/commits.txt"
  run determine_bump "$TMP/commits.txt"
  [ "$output" = "minor" ]
}

@test "determine_bump returns major for a feat! breaking commit" {
  printf 'feat!: drop support for the old API\n' > "$TMP/commits.txt"
  run determine_bump "$TMP/commits.txt"
  [ "$output" = "major" ]
}

@test "determine_bump returns major for a BREAKING CHANGE footer" {
  cat > "$TMP/commits.txt" <<'LOG'
fix: tidy logs

BREAKING CHANGE: config format changed
LOG
  run determine_bump "$TMP/commits.txt"
  [ "$output" = "major" ]
}

@test "determine_bump picks the highest precedence among many commits" {
  cat > "$TMP/commits.txt" <<'LOG'
fix: small fix
feat: a feature
chore: noise
LOG
  run determine_bump "$TMP/commits.txt"
  [ "$output" = "minor" ]
}

@test "determine_bump returns none when nothing is releasable" {
  cat > "$TMP/commits.txt" <<'LOG'
chore: update deps
docs: fix a typo
LOG
  run determine_bump "$TMP/commits.txt"
  [ "$output" = "none" ]
}

# --- bump_version ---------------------------------------------------------

@test "bump_version increments the patch component" {
  run bump_version "1.4.9" "patch"
  [ "$output" = "1.4.10" ]
}

@test "bump_version increments minor and resets patch" {
  run bump_version "1.4.9" "minor"
  [ "$output" = "1.5.0" ]
}

@test "bump_version increments major and resets minor and patch" {
  run bump_version "1.4.9" "major"
  [ "$output" = "2.0.0" ]
}

@test "bump_version leaves the version unchanged for none" {
  run bump_version "1.4.9" "none"
  [ "$output" = "1.4.9" ]
}

# --- update_version_file --------------------------------------------------

@test "update_version_file rewrites a plain VERSION file" {
  printf '1.2.3\n' > "$TMP/VERSION"
  run update_version_file "$TMP/VERSION" "1.3.0"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/VERSION")" = "1.3.0" ]
}

@test "update_version_file rewrites only the version field in package.json" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "0.3.4",
  "description": "version 0.3.4 of demo"
}
JSON
  run update_version_file "$TMP/package.json" "0.4.0"
  [ "$status" -eq 0 ]
  # The version field changed...
  run parse_version "$TMP/package.json"
  [ "$output" = "0.4.0" ]
  # ...but the description string was left untouched.
  grep -q 'version 0.3.4 of demo' "$TMP/package.json"
}

# --- generate_changelog ---------------------------------------------------

@test "generate_changelog writes a header and bullet list of commits" {
  cat > "$TMP/commits.txt" <<'LOG'
feat: add export command
fix: handle empty input
chore: noise that should be skipped
LOG
  run generate_changelog "$TMP/commits.txt" "1.3.0" "$TMP/CHANGELOG.md" "2026-06-27"
  [ "$status" -eq 0 ]
  grep -q '## \[1.3.0\] - 2026-06-27' "$TMP/CHANGELOG.md"
  grep -q '### Features' "$TMP/CHANGELOG.md"
  grep -q -- '- add export command' "$TMP/CHANGELOG.md"
  grep -q '### Fixes' "$TMP/CHANGELOG.md"
  grep -q -- '- handle empty input' "$TMP/CHANGELOG.md"
  # Non-conventional noise must not appear.
  ! grep -q 'noise that should be skipped' "$TMP/CHANGELOG.md"
}

@test "generate_changelog prepends new entries above older ones" {
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n' > "$TMP/CHANGELOG.md"
  printf 'feat: another feature\n' > "$TMP/commits.txt"
  run generate_changelog "$TMP/commits.txt" "1.1.0" "$TMP/CHANGELOG.md" "2026-06-27"
  [ "$status" -eq 0 ]
  # The new 1.1.0 entry must appear before the existing 1.0.0 entry.
  new_line="$(grep -n '\[1.1.0\]' "$TMP/CHANGELOG.md" | cut -d: -f1)"
  old_line="$(grep -n '\[1.0.0\]' "$TMP/CHANGELOG.md" | cut -d: -f1)"
  [ "$new_line" -lt "$old_line" ]
}

# --- main (end-to-end CLI) ------------------------------------------------

@test "main bumps a minor release end to end and prints the new version" {
  printf '1.1.0\n' > "$TMP/VERSION"
  printf 'feat: add the thing\n' > "$TMP/commits.txt"
  run bash "$SCRIPT" \
    --version-file "$TMP/VERSION" \
    --commits "$TMP/commits.txt" \
    --changelog "$TMP/CHANGELOG.md" \
    --date "2026-06-27"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "1.2.0" ]                   # new version on stdout (last line)
  [ "$(cat "$TMP/VERSION")" = "1.2.0" ]         # file updated
  grep -q '## \[1.2.0\] - 2026-06-27' "$TMP/CHANGELOG.md"
}

@test "main exits 0 without changing files when there is nothing to release" {
  printf '1.1.0\n' > "$TMP/VERSION"
  printf 'chore: housekeeping\n' > "$TMP/commits.txt"
  run bash "$SCRIPT" \
    --version-file "$TMP/VERSION" \
    --commits "$TMP/commits.txt" \
    --changelog "$TMP/CHANGELOG.md"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "1.1.0" ]                    # unchanged version echoed (last line)
  [ "$(cat "$TMP/VERSION")" = "1.1.0" ]          # file untouched
  [ ! -f "$TMP/CHANGELOG.md" ]                   # no changelog written
}

@test "main --dry-run prints the new version but leaves files untouched" {
  printf '1.1.0\n' > "$TMP/VERSION"
  printf 'fix: a fix\n' > "$TMP/commits.txt"
  run bash "$SCRIPT" \
    --version-file "$TMP/VERSION" \
    --commits "$TMP/commits.txt" \
    --changelog "$TMP/CHANGELOG.md" \
    --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "1.1.1" ]
  [ "$(cat "$TMP/VERSION")" = "1.1.0" ]          # unchanged on dry-run
  [ ! -f "$TMP/CHANGELOG.md" ]
}

@test "main fails with a helpful message when the version file is missing" {
  run bash "$SCRIPT" \
    --version-file "$TMP/nope" \
    --commits "$TMP/commits.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "main prints usage with --help" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
