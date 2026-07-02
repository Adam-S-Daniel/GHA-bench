#!/usr/bin/env bats
# Unit tests for bump-version.sh. We source the script (instead of executing
# it) so we can call its internal functions directly. The script guards its
# "main" execution behind a BASH_SOURCE check so sourcing has no side effects.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    FIXTURES="$SCRIPT_DIR/test/fixtures"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/bump-version.sh"

    # Work in a throwaway temp directory so tests never touch real fixtures.
    TMPDIR_TEST="$(mktemp -d)"
    cd "$TMPDIR_TEST" || exit 1
}

teardown() {
    cd "$SCRIPT_DIR" || true
    rm -rf "$TMPDIR_TEST"
}

# --- parse_version ---------------------------------------------------------

@test "parse_version splits a valid semver into major minor patch" {
    run parse_version "1.4.2"
    [ "$status" -eq 0 ]
    [ "$output" = "1 4 2" ]
}

@test "parse_version rejects a malformed version string" {
    run parse_version "not-a-version"
    [ "$status" -ne 0 ]
}

# --- determine_bump_type ----------------------------------------------------

@test "determine_bump_type returns patch when only fix/chore/docs commits exist" {
    run determine_bump_type "$FIXTURES/commits-patch.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "patch" ]
}

@test "determine_bump_type returns minor when a feat commit exists" {
    run determine_bump_type "$FIXTURES/commits-minor.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "minor" ]
}

@test "determine_bump_type returns major when a breaking change marker exists" {
    run determine_bump_type "$FIXTURES/commits-major.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "major" ]
}

@test "determine_bump_type returns none when no releasable commits exist" {
    run determine_bump_type "$FIXTURES/commits-none.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "determine_bump_type errors on a missing commits file" {
    run determine_bump_type "$FIXTURES/does-not-exist.txt"
    [ "$status" -ne 0 ]
}

# --- compute_next_version ---------------------------------------------------

@test "compute_next_version bumps patch" {
    run compute_next_version "1.4.2" "patch"
    [ "$status" -eq 0 ]
    [ "$output" = "1.4.3" ]
}

@test "compute_next_version bumps minor and resets patch" {
    run compute_next_version "1.4.2" "minor"
    [ "$status" -eq 0 ]
    [ "$output" = "1.5.0" ]
}

@test "compute_next_version bumps major and resets minor/patch" {
    run compute_next_version "1.4.2" "major"
    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
}

@test "compute_next_version returns the same version for bump type none" {
    run compute_next_version "1.4.2" "none"
    [ "$status" -eq 0 ]
    [ "$output" = "1.4.2" ]
}

@test "compute_next_version rejects an unknown bump type" {
    run compute_next_version "1.4.2" "banana"
    [ "$status" -ne 0 ]
}

# --- read_current_version / write_version -----------------------------------

@test "read_current_version reads a plain VERSION file" {
    echo "0.9.1" > VERSION
    run read_current_version "VERSION"
    [ "$status" -eq 0 ]
    [ "$output" = "0.9.1" ]
}

@test "read_current_version reads the version field from package.json" {
    cp "$FIXTURES/package.json" package.json
    run read_current_version "package.json"
    [ "$status" -eq 0 ]
    [ "$output" = "1.4.2" ]
}

@test "read_current_version errors on a missing file" {
    run read_current_version "nope.txt"
    [ "$status" -ne 0 ]
}

@test "write_version updates a plain VERSION file" {
    echo "0.9.1" > VERSION
    write_version "VERSION" "0.10.0"
    run cat VERSION
    [ "$output" = "0.10.0" ]
}

@test "write_version updates the version field in package.json, preserving other fields" {
    cp "$FIXTURES/package.json" package.json
    write_version "package.json" "2.0.0"
    run read_current_version "package.json"
    [ "$output" = "2.0.0" ]
    run grep -c '"name": "sample-project"' package.json
    [ "$output" = "1" ]
}

# --- generate_changelog_entry ------------------------------------------------

@test "generate_changelog_entry prepends a new entry listing each commit" {
    run generate_changelog_entry "1.5.0" "$FIXTURES/commits-minor.txt" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [ -f "CHANGELOG.md" ]
    grep -q "## 1.5.0" CHANGELOG.md
    grep -q -- "- feat(auth): add OAuth2 login support" CHANGELOG.md
    grep -q -- "- fix: handle null token on refresh" CHANGELOG.md
}

@test "generate_changelog_entry prepends new entries above older ones" {
    echo "## 1.4.2" > CHANGELOG.md
    echo "- fix: old entry" >> CHANGELOG.md
    generate_changelog_entry "1.5.0" "$FIXTURES/commits-minor.txt" "CHANGELOG.md"
    run head -n1 CHANGELOG.md
    [ "$output" = "## 1.5.0" ]
    grep -q "## 1.4.2" CHANGELOG.md
}

# --- run_bump (end-to-end orchestration) ------------------------------------

@test "run_bump performs a full minor bump: updates VERSION, writes changelog, prints new version" {
    echo "1.4.2" > VERSION
    run run_bump "VERSION" "$FIXTURES/commits-minor.txt" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [ "$output" = "1.5.0" ]
    [ "$(cat VERSION)" = "1.5.0" ]
    grep -q "## 1.5.0" CHANGELOG.md
}

@test "run_bump performs a full major bump on package.json" {
    cp "$FIXTURES/package.json" package.json
    run run_bump "package.json" "$FIXTURES/commits-major.txt" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [ "$output" = "2.0.0" ]
    run read_current_version "package.json"
    [ "$output" = "2.0.0" ]
}

@test "run_bump leaves the version file untouched and exits nonzero when no releasable commits exist" {
    echo "1.4.2" > VERSION
    run run_bump "VERSION" "$FIXTURES/commits-none.txt" "CHANGELOG.md"
    [ "$status" -ne 0 ]
    [ "$(cat VERSION)" = "1.4.2" ]
    [ ! -f "CHANGELOG.md" ]
}
