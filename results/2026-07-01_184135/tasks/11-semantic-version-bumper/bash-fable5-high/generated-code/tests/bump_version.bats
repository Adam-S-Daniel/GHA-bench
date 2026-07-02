#!/usr/bin/env bats
# =============================================================================
# Unit tests for bump_version.sh — built with red/green TDD.
#
# Approach:
#   * Each TDD cycle added a failing test first, then the minimum production
#     code to make it green, then a refactor pass (see comments in the script).
#   * Pure functions (parsing, bump math, changelog rendering) are tested by
#     sourcing the script with BUMP_VERSION_LIB=1 so main() does not run.
#   * End-to-end behaviour is tested by invoking the CLI against mock commit
#     logs (tests/fixtures/*.txt) and throw-away version files in $BATS_TEST_TMPDIR.
# =============================================================================

# Resolve repo root relative to this test file so bats can run from anywhere.
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bump_version.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures"
  # Load the script as a library (functions only, main() suppressed).
  # shellcheck disable=SC1090
  BUMP_VERSION_LIB=1 source "$SCRIPT"
}

# --- TDD cycle 7: end-to-end CLI ----------------------------------------------

@test "CLI: feat commits bump 1.1.0 -> 1.2.0 and update the VERSION file" {
  echo "1.1.0" > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" --version-file "$BATS_TEST_TMPDIR/VERSION" \
                --commits "$FIXTURES/commits_feat.txt" \
                --changelog "$BATS_TEST_TMPDIR/CHANGELOG.md" \
                --date 2026-07-02
  [ "$status" -eq 0 ]
  # The new version is the last line of stdout so CI can capture it directly.
  [ "${lines[-1]}" = "1.2.0" ]
  [ "$(cat "$BATS_TEST_TMPDIR/VERSION")" = "1.2.0" ]
  grep -q '## 1.2.0 (2026-07-02)' "$BATS_TEST_TMPDIR/CHANGELOG.md"
  grep -q -- '- add user profile page' "$BATS_TEST_TMPDIR/CHANGELOG.md"
}

@test "CLI: fix commits bump package.json 2.3.4 -> 2.3.5" {
  cp "$FIXTURES/package.json" "$BATS_TEST_TMPDIR/package.json"
  run "$SCRIPT" --version-file "$BATS_TEST_TMPDIR/package.json" \
                --commits "$FIXTURES/commits_fix.txt" \
                --changelog "$BATS_TEST_TMPDIR/CHANGELOG.md" \
                --date 2026-07-02
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "2.3.5" ]
  grep -q '"version": "2.3.5"' "$BATS_TEST_TMPDIR/package.json"
}

@test "CLI: breaking commits bump 1.1.0 -> 2.0.0" {
  echo "1.1.0" > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" --version-file "$BATS_TEST_TMPDIR/VERSION" \
                --commits "$FIXTURES/commits_breaking.txt" \
                --changelog "$BATS_TEST_TMPDIR/CHANGELOG.md" \
                --date 2026-07-02
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "2.0.0" ]
  grep -q '### Breaking Changes' "$BATS_TEST_TMPDIR/CHANGELOG.md"
}

@test "CLI: no release-worthy commits keeps version and skips the changelog" {
  echo "1.1.0" > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" --version-file "$BATS_TEST_TMPDIR/VERSION" \
                --commits "$FIXTURES/commits_none.txt" \
                --changelog "$BATS_TEST_TMPDIR/CHANGELOG.md" \
                --date 2026-07-02
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "1.1.0" ]
  [ "$(cat "$BATS_TEST_TMPDIR/VERSION")" = "1.1.0" ]
  [ ! -f "$BATS_TEST_TMPDIR/CHANGELOG.md" ]
  [[ "$output" == *"no version bump needed"* ]]
}

@test "CLI: missing --version-file argument is a usage error" {
  run "$SCRIPT" --commits "$FIXTURES/commits_feat.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--version-file is required"* ]]
}

@test "CLI: unknown option produces a helpful error" {
  run "$SCRIPT" --frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
  [[ "$output" == *"Usage:"* ]]
}

# --- TDD cycle 6: changelog generation ----------------------------------------

@test "render_changelog_entry groups commits under Breaking/Features/Fixes" {
  run render_changelog_entry "2.0.0" "2026-07-02" "$FIXTURES/commits_breaking.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 2.0.0 (2026-07-02)"* ]]
  [[ "$output" == *"### Breaking Changes"* ]]
  [[ "$output" == *"- drop support for the v1 API"* ]]
  [[ "$output" == *"### Features"* ]]
  [[ "$output" == *"- add pagination to list endpoints"* ]]
  [[ "$output" == *"### Fixes"* ]]
  [[ "$output" == *"- correct off-by-one in cursor handling"* ]]
}

@test "render_changelog_entry omits empty sections" {
  run render_changelog_entry "1.2.0" "2026-07-02" "$FIXTURES/commits_feat.txt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"### Breaking Changes"* ]]
  [[ "$output" == *"### Features"* ]]
  [[ "$output" == *"### Fixes"* ]]   # fixture has one fix(api) commit
}

@test "prepend_changelog puts the newest entry on top and creates the file" {
  local changelog="$BATS_TEST_TMPDIR/CHANGELOG.md"
  prepend_changelog "$changelog" "$(render_changelog_entry "1.2.0" "2026-07-02" "$FIXTURES/commits_feat.txt")"
  prepend_changelog "$changelog" "$(render_changelog_entry "1.2.1" "2026-07-03" "$FIXTURES/commits_fix.txt")"
  run head -n1 "$changelog"
  [ "$output" = "## 1.2.1 (2026-07-03)" ]
  grep -q '## 1.2.0 (2026-07-02)' "$changelog"
}

# --- TDD cycle 5: writing the new version back --------------------------------

@test "write_version rewrites a plain VERSION file" {
  echo "1.1.0" > "$BATS_TEST_TMPDIR/VERSION"
  run write_version "$BATS_TEST_TMPDIR/VERSION" "1.2.0"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/VERSION")" = "1.2.0" ]
}

@test "write_version updates only the version field in package.json" {
  cp "$FIXTURES/package.json" "$BATS_TEST_TMPDIR/package.json"
  run write_version "$BATS_TEST_TMPDIR/package.json" "2.4.0"
  [ "$status" -eq 0 ]
  grep -q '"version": "2.4.0"' "$BATS_TEST_TMPDIR/package.json"
  # The rest of the document must be untouched.
  grep -q '"name": "demo-package"' "$BATS_TEST_TMPDIR/package.json"
  grep -q '"private": true' "$BATS_TEST_TMPDIR/package.json"
}

# --- TDD cycle 4: version arithmetic ------------------------------------------

@test "apply_bump: major resets minor and patch" {
  run apply_bump "1.2.3" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "apply_bump: minor resets patch" {
  run apply_bump "1.2.3" "minor"
  [ "$status" -eq 0 ]
  [ "$output" = "1.3.0" ]
}

@test "apply_bump: patch increments last component" {
  run apply_bump "1.2.3" "patch"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]
}

@test "apply_bump: none keeps the version unchanged" {
  run apply_bump "1.2.3" "none"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "apply_bump rejects an unknown bump type" {
  run apply_bump "1.2.3" "gigantic"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown bump type"* ]]
}

# --- TDD cycle 3: bump-type detection from conventional commits --------------

@test "determine_bump: feat commits yield minor" {
  run determine_bump "$FIXTURES/commits_feat.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "minor" ]
}

@test "determine_bump: fix-only commits yield patch" {
  run determine_bump "$FIXTURES/commits_fix.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "patch" ]
}

@test "determine_bump: bang suffix (feat!:) yields major even with feat/fix present" {
  run determine_bump "$FIXTURES/commits_breaking.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "major" ]
}

@test "determine_bump: BREAKING CHANGE footer yields major" {
  run determine_bump "$FIXTURES/commits_breaking_footer.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "major" ]
}

@test "determine_bump: docs/chore-only commits yield none" {
  run determine_bump "$FIXTURES/commits_none.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "determine_bump errors on a missing commit log" {
  run determine_bump "$BATS_TEST_TMPDIR/absent.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit log not found"* ]]
}

# --- TDD cycle 2: package.json support ---------------------------------------

@test "read_current_version reads the version field from package.json" {
  cp "$FIXTURES/package.json" "$BATS_TEST_TMPDIR/package.json"
  run read_current_version "$BATS_TEST_TMPDIR/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "2.3.4" ]
}

@test "read_current_version errors on package.json without a version field" {
  echo '{"name": "x"}' > "$BATS_TEST_TMPDIR/package.json"
  run read_current_version "$BATS_TEST_TMPDIR/package.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no \"version\" field"* ]]
}

# --- TDD cycle 1: reading the current version -------------------------------

@test "read_current_version reads a plain VERSION file" {
  echo "1.1.0" > "$BATS_TEST_TMPDIR/VERSION"
  run read_current_version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
}

@test "read_current_version errors on a missing file" {
  run read_current_version "$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "read_current_version rejects a malformed version" {
  echo "not-a-version" > "$BATS_TEST_TMPDIR/VERSION"
  run read_current_version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid semantic version"* ]]
}
