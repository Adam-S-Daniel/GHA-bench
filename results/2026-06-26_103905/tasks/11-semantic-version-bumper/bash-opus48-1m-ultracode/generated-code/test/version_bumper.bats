#!/usr/bin/env bats
#
# Unit tests for semantic-version-bumper.sh (TDD red/green/refactor).
#
# These tests source the script (which is written to be source-safe: it only
# runs main() when executed directly, not when sourced) and exercise each
# function in isolation. Fixtures are created per-test in a temp dir so tests
# are hermetic and order-independent.

setup() {
  # Absolute path to the script under test (this file lives in ./test/).
  SCRIPT="${BATS_TEST_DIRNAME}/../semantic-version-bumper.sh"
  # Source it so the svb_* functions become available in this shell.
  source "$SCRIPT"
  # A scratch dir unique to each test.
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# svb_read_version: extract the current version string from a version file.
# ---------------------------------------------------------------------------

@test "svb_read_version reads a plain VERSION file" {
  printf '1.2.3\n' > "$TMP/VERSION"
  run svb_read_version "$TMP/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}

@test "svb_read_version strips a leading 'v' from a plain file" {
  printf 'v0.4.1\n' > "$TMP/VERSION"
  run svb_read_version "$TMP/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "0.4.1" ]
}

@test "svb_read_version reads version from package.json" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "2.5.0",
  "scripts": { "test": "echo hi" }
}
JSON
  run svb_read_version "$TMP/package.json"
  [ "$status" -eq 0 ]
  [ "$output" = "2.5.0" ]
}

@test "svb_read_version errors clearly when the file is missing" {
  run svb_read_version "$TMP/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "svb_read_version errors when package.json has no version field" {
  printf '{ "name": "x" }\n' > "$TMP/package.json"
  run svb_read_version "$TMP/package.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no version"* ]]
}

# ---------------------------------------------------------------------------
# svb_validate_semver: accept x.y.z (optionally with -prerelease / +build).
# ---------------------------------------------------------------------------

@test "svb_validate_semver accepts a clean version" {
  run svb_validate_semver "1.2.3"
  [ "$status" -eq 0 ]
}

@test "svb_validate_semver accepts a prerelease/build version" {
  run svb_validate_semver "1.2.3-rc.1+build.5"
  [ "$status" -eq 0 ]
}

@test "svb_validate_semver rejects a non-semver string" {
  run svb_validate_semver "1.2"
  [ "$status" -ne 0 ]
}

@test "svb_validate_semver rejects garbage" {
  run svb_validate_semver "not-a-version"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# svb_bump_version VERSION BUMP_TYPE -> new version
# ---------------------------------------------------------------------------

@test "svb_bump_version major: 1.2.3 -> 2.0.0" {
  run svb_bump_version "1.2.3" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "svb_bump_version minor: 1.2.3 -> 1.3.0" {
  run svb_bump_version "1.2.3" "minor"
  [ "$status" -eq 0 ]
  [ "$output" = "1.3.0" ]
}

@test "svb_bump_version patch: 1.2.3 -> 1.2.4" {
  run svb_bump_version "1.2.3" "patch"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]
}

@test "svb_bump_version drops a prerelease suffix when bumping" {
  run svb_bump_version "1.2.3-rc.1" "patch"
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]
}

@test "svb_bump_version major from 0.x: 0.5.9 -> 1.0.0" {
  run svb_bump_version "0.5.9" "major"
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.0" ]
}

@test "svb_bump_version rejects an invalid current version" {
  run svb_bump_version "1.2" "patch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "svb_bump_version rejects an unknown bump type" {
  run svb_bump_version "1.2.3" "sideways"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# svb_determine_bump COMMITS_FILE -> major|minor|patch|none
# Commits file holds one conventional-commit header per line.
# ---------------------------------------------------------------------------

@test "svb_determine_bump: a feat commit yields minor" {
  printf 'feat: add login page\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "minor" ]
}

@test "svb_determine_bump: a scoped feat yields minor" {
  printf 'feat(auth): add oauth support\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "minor" ]
}

@test "svb_determine_bump: a fix commit yields patch" {
  printf 'fix: correct null deref\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "patch" ]
}

@test "svb_determine_bump: feat! (bang) yields major" {
  printf 'feat!: drop node 14 support\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "major" ]
}

@test "svb_determine_bump: scoped feat(api)! yields major" {
  printf 'feat(api)!: change response shape\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "major" ]
}

@test "svb_determine_bump: BREAKING CHANGE footer token yields major" {
  printf 'refactor: rework module\nBREAKING CHANGE: removed legacy API\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "major" ]
}

@test "svb_determine_bump: feat wins over fix (highest precedence)" {
  printf 'fix: small bug\nfeat: shiny feature\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "minor" ]
}

@test "svb_determine_bump: breaking wins over feat and fix" {
  printf 'fix: bug\nfeat: feature\nfeat!: breaking thing\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "major" ]
}

@test "svb_determine_bump: only chore/docs yields none" {
  printf 'chore: bump deps\ndocs: tidy readme\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "none" ]
}

@test "svb_determine_bump: non-conventional lines are ignored -> none" {
  printf 'Merge branch main into dev\nupdate stuff\n' > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "none" ]
}

@test "svb_determine_bump: empty commits file yields none" {
  : > "$TMP/c.txt"
  run svb_determine_bump "$TMP/c.txt"
  [ "$output" = "none" ]
}

@test "svb_determine_bump: missing commits file errors" {
  run svb_determine_bump "$TMP/missing.txt"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# svb_generate_changelog NEW_VERSION COMMITS_FILE DATE -> markdown entry
# ---------------------------------------------------------------------------

@test "svb_generate_changelog emits a dated version header" {
  printf 'feat: add login page\n' > "$TMP/c.txt"
  run svb_generate_changelog "1.2.0" "$TMP/c.txt" "2026-06-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## [1.2.0] - 2026-06-28"* ]]
}

@test "svb_generate_changelog lists features under a Features heading" {
  printf 'feat: add login page\n' > "$TMP/c.txt"
  run svb_generate_changelog "1.2.0" "$TMP/c.txt" "2026-06-28"
  [[ "$output" == *"### Features"* ]]
  [[ "$output" == *"- add login page"* ]]
}

@test "svb_generate_changelog lists fixes under a Bug Fixes heading" {
  printf 'fix: correct null deref\n' > "$TMP/c.txt"
  run svb_generate_changelog "1.0.1" "$TMP/c.txt" "2026-06-28"
  [[ "$output" == *"### Bug Fixes"* ]]
  [[ "$output" == *"- correct null deref"* ]]
}

@test "svb_generate_changelog prefixes scoped commits with the scope" {
  printf 'feat(auth): add oauth support\n' > "$TMP/c.txt"
  run svb_generate_changelog "1.2.0" "$TMP/c.txt" "2026-06-28"
  [[ "$output" == *"- **auth:** add oauth support"* ]]
}

@test "svb_generate_changelog records breaking changes in their own section" {
  printf 'feat!: drop node 14 support\n' > "$TMP/c.txt"
  run svb_generate_changelog "2.0.0" "$TMP/c.txt" "2026-06-28"
  [[ "$output" == *"### BREAKING CHANGES"* ]]
  [[ "$output" == *"drop node 14 support"* ]]
}

@test "svb_generate_changelog omits sections that have no commits" {
  printf 'fix: a bug\n' > "$TMP/c.txt"
  run svb_generate_changelog "1.0.1" "$TMP/c.txt" "2026-06-28"
  [[ "$output" != *"### Features"* ]]
  [[ "$output" != *"### BREAKING CHANGES"* ]]
}

# ---------------------------------------------------------------------------
# svb_write_version FILE NEW_VERSION  (in-place update of plain or json file)
# ---------------------------------------------------------------------------

@test "svb_write_version updates a plain version file" {
  printf '1.2.3\n' > "$TMP/VERSION"
  run svb_write_version "$TMP/VERSION" "1.3.0"
  [ "$status" -eq 0 ]
  run svb_read_version "$TMP/VERSION"
  [ "$output" = "1.3.0" ]
}

@test "svb_write_version updates the version field in package.json" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "1.2.3",
  "license": "MIT"
}
JSON
  run svb_write_version "$TMP/package.json" "2.0.0"
  [ "$status" -eq 0 ]
  run svb_read_version "$TMP/package.json"
  [ "$output" = "2.0.0" ]
  # The rest of the file must be preserved.
  grep -q '"name": "demo"' "$TMP/package.json"
  grep -q '"license": "MIT"' "$TMP/package.json"
}

# ---------------------------------------------------------------------------
# svb_prepend_changelog FILE ENTRY  (newest entries first, header preserved)
# ---------------------------------------------------------------------------

@test "svb_prepend_changelog creates the file with a header if missing" {
  run svb_prepend_changelog "$TMP/CHANGELOG.md" "## [1.0.0] - 2026-06-28"$'\n'"### Features"
  [ "$status" -eq 0 ]
  grep -q "# Changelog" "$TMP/CHANGELOG.md"
  grep -q "## \[1.0.0\] - 2026-06-28" "$TMP/CHANGELOG.md"
}

@test "svb_prepend_changelog puts new entries above older ones" {
  svb_prepend_changelog "$TMP/CHANGELOG.md" "## [1.0.0] - 2026-06-27"
  svb_prepend_changelog "$TMP/CHANGELOG.md" "## [1.1.0] - 2026-06-28"
  # The 1.1.0 header must appear before the 1.0.0 header in the file.
  local newer older
  newer="$(grep -n '1.1.0' "$TMP/CHANGELOG.md" | head -1 | cut -d: -f1)"
  older="$(grep -n '1.0.0' "$TMP/CHANGELOG.md" | head -1 | cut -d: -f1)"
  [ "$newer" -lt "$older" ]
}

# ---------------------------------------------------------------------------
# main / CLI: end-to-end behaviour invoked as a subprocess (as CI does).
# ---------------------------------------------------------------------------

@test "CLI: feat commit bumps minor, updates VERSION and changelog" {
  printf '1.1.0\n' > "$TMP/VERSION"
  printf 'feat: add dashboard\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file VERSION --commits-file commits.txt \
      --changelog-file CHANGELOG.md --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"New version: 1.2.0"* ]]
  [[ "$output" == *"NEW_VERSION=1.2.0"* ]]
  [ "$(cat VERSION)" = "1.2.0" ]
  grep -q "## \[1.2.0\] - 2026-06-28" CHANGELOG.md
  grep -q "add dashboard" CHANGELOG.md
}

@test "CLI: fix commit bumps patch" {
  printf '2.3.4\n' > "$TMP/VERSION"
  printf 'fix: handle empty input\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file VERSION --commits-file commits.txt --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_VERSION=2.3.5"* ]]
}

@test "CLI: breaking change bumps major" {
  printf '1.4.2\n' > "$TMP/VERSION"
  printf 'feat!: rewrite public API\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file VERSION --commits-file commits.txt --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_VERSION=2.0.0"* ]]
  [ "$(cat VERSION)" = "2.0.0" ]
}

@test "CLI: package.json is detected and updated" {
  cat > "$TMP/package.json" <<'JSON'
{
  "name": "demo",
  "version": "0.9.0"
}
JSON
  printf 'feat: ship it\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file package.json --commits-file commits.txt --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_VERSION=0.10.0"* ]]
  grep -q '"version": "0.10.0"' package.json
  grep -q '"name": "demo"' package.json
}

@test "CLI: no bump-worthy commits leaves files unchanged, exits 0" {
  printf '1.0.0\n' > "$TMP/VERSION"
  printf 'chore: tidy\ndocs: update readme\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file VERSION --commits-file commits.txt --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"No version bump"* ]]
  [[ "$output" == *"NEW_VERSION=1.0.0"* ]]
  [ "$(cat VERSION)" = "1.0.0" ]
  [ ! -f CHANGELOG.md ]
}

@test "CLI: --dry-run computes but does not modify files" {
  printf '1.0.0\n' > "$TMP/VERSION"
  printf 'feat: a thing\n' > "$TMP/commits.txt"
  cd "$TMP"
  run bash "$SCRIPT" --version-file VERSION --commits-file commits.txt --dry-run --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_VERSION=1.1.0"* ]]
  # File untouched, changelog not created.
  [ "$(cat VERSION)" = "1.0.0" ]
  [ ! -f CHANGELOG.md ]
}

@test "CLI: --help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "CLI: missing version file errors with a clear message" {
  cd "$TMP"
  printf 'feat: x\n' > commits.txt
  run bash "$SCRIPT" --version-file does-not-exist --commits-file commits.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "CLI: unknown option errors" {
  run bash "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "CLI: writes new_version to GITHUB_OUTPUT when set" {
  printf '1.0.0\n' > "$TMP/VERSION"
  printf 'feat: thing\n' > "$TMP/commits.txt"
  cd "$TMP"
  GITHUB_OUTPUT="$TMP/gh_out" run bash "$SCRIPT" \
      --version-file VERSION --commits-file commits.txt --date 2026-06-28
  [ "$status" -eq 0 ]
  grep -q "new_version=1.1.0" "$TMP/gh_out"
  grep -q "bump_type=minor" "$TMP/gh_out"
}

@test "CLI: falls back to git log when no commits file is given" {
  cd "$TMP"
  git init -q
  git config user.email t@t.t
  git config user.name t
  printf '1.0.0\n' > VERSION
  git add VERSION
  git commit -q -m "chore: initial"
  git commit -q --allow-empty -m "feat: a real feature"
  run bash "$SCRIPT" --version-file VERSION --date 2026-06-28
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_VERSION=1.1.0"* ]]
}
