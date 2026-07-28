#!/usr/bin/env bats

# Test suite for semantic version bumper script using TDD methodology
# Tests will guide the implementation of the version bumper

setup() {
  export TMPDIR=$(mktemp -d)
  export TEST_REPO_DIR="$TMPDIR/test_repo"
  mkdir -p "$TEST_REPO_DIR"
  cd "$TEST_REPO_DIR"

  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Source the main script
  source "$BATS_TEST_DIRNAME/semantic_version_bumper.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

# === FIXTURE CREATION TESTS ===

@test "fixture: create version file with initial version" {
  echo '{"version": "1.0.0"}' > package.json
  run get_current_version "package.json"
  assert_success
  assert_output "1.0.0"
}

@test "fixture: parse version from package.json" {
  echo '{"version": "2.3.4", "name": "test"}' > package.json
  run get_current_version "package.json"
  assert_success
  assert_output "2.3.4"
}

@test "fixture: create mock commit logs" {
  git commit --allow-empty -m "feat: add new feature"
  run get_commits_since_tag "v1.0.0"
  assert_success
  assert_output --regexp "feat: add new feature"
}

# === VERSION PARSING TESTS ===

@test "parse_semver: extract major version from 1.2.3" {
  run get_major_version "1.2.3"
  assert_success
  assert_output "1"
}

@test "parse_semver: extract minor version from 1.2.3" {
  run get_minor_version "1.2.3"
  assert_success
  assert_output "2"
}

@test "parse_semver: extract patch version from 1.2.3" {
  run get_patch_version "1.2.3"
  assert_success
  assert_output "3"
}

# === BUMP LOGIC TESTS ===

@test "bump_logic: detect feat commits trigger minor bump" {
  git commit --allow-empty -m "feat: add new feature"
  run detect_bump_type
  assert_success
  assert_output "minor"
}

@test "bump_logic: detect fix commits trigger patch bump" {
  git commit --allow-empty -m "fix: resolve bug"
  run detect_bump_type
  assert_success
  assert_output "patch"
}

@test "bump_logic: detect BREAKING CHANGE trigger major bump" {
  git commit --allow-empty -m "refactor: remove deprecated API

BREAKING CHANGE: old API no longer supported"
  run detect_bump_type
  assert_success
  assert_output "major"
}

@test "bump_logic: bump patch version 1.2.3 -> 1.2.4" {
  run bump_version "1.2.3" "patch"
  assert_success
  assert_output "1.2.4"
}

@test "bump_logic: bump minor version 1.2.3 -> 1.3.0" {
  run bump_version "1.2.3" "minor"
  assert_success
  assert_output "1.3.0"
}

@test "bump_logic: bump major version 1.2.3 -> 2.0.0" {
  run bump_version "1.2.3" "major"
  assert_success
  assert_output "2.0.0"
}

@test "bump_logic: handle zero versions 0.0.1 -> patch -> 0.0.2" {
  run bump_version "0.0.1" "patch"
  assert_success
  assert_output "0.0.2"
}

# === FILE UPDATE TESTS ===

@test "file_update: update version in package.json" {
  echo '{"version": "1.0.0"}' > package.json
  run update_version_in_file "package.json" "1.0.1"
  assert_success
  grep -q '"version": "1.0.1"' package.json
}

@test "file_update: update version in version.txt file" {
  echo "1.0.0" > version.txt
  run update_version_in_file "version.txt" "1.0.1"
  assert_success
  grep -q "1.0.1" version.txt
}

# === CHANGELOG GENERATION TESTS ===

@test "changelog: generate entry from single commit" {
  git commit --allow-empty -m "initial commit"
  git tag v1.0.0
  git commit --allow-empty -m "feat: add login feature"
  run generate_changelog_entry
  assert_success
  assert_output --regexp "add login feature"
}

@test "changelog: collect multiple commits in changelog" {
  git commit --allow-empty -m "initial commit"
  git tag v1.0.0
  git commit --allow-empty -m "feat: add login"
  git commit --allow-empty -m "fix: resolve session bug"
  run generate_changelog_entry
  assert_success
  assert_output --regexp "add login"
  assert_output --regexp "resolve session bug"
}

@test "changelog: format changelog entry with version and date" {
  git commit --allow-empty -m "initial commit"
  git tag v1.0.0
  git commit --allow-empty -m "feat: add feature"
  run generate_changelog_entry "1.1.0"
  assert_success
  assert_output --regexp "1.1.0"
}

# === INTEGRATION TESTS ===

@test "integration: full workflow - patch bump" {
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit -m "initial: setup"
  git tag v1.0.0

  # Add a fix commit
  git commit --allow-empty -m "fix: resolve issue"

  run semantic_version_bumper "package.json"
  assert_success
  assert_output --regexp "1.0.1"
}

@test "integration: full workflow - minor bump" {
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit -m "initial: setup"
  git tag v1.0.0

  # Add a feature commit
  git commit --allow-empty -m "feat: add new feature"

  run semantic_version_bumper "package.json"
  assert_success
  assert_output --regexp "1.1.0"
}

@test "integration: full workflow - major bump on breaking change" {
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit -m "initial: setup"
  git tag v1.0.0

  # Add a breaking change
  git commit --allow-empty -m "refactor: remove deprecated API

BREAKING CHANGE: API v1 removed"

  run semantic_version_bumper "package.json"
  assert_success
  assert_output --regexp "2.0.0"
}

# === ERROR HANDLING TESTS ===

@test "error: fail gracefully on missing file" {
  run semantic_version_bumper "nonexistent.json"
  assert_failure
  assert_output --regexp "Error.*not found"
}

@test "error: fail gracefully on invalid json" {
  echo 'invalid json' > package.json
  run semantic_version_bumper "package.json"
  assert_failure
  assert_output --regexp "Error.*invalid"
}

@test "error: fail gracefully on missing version field" {
  echo '{"name": "test"}' > package.json
  run semantic_version_bumper "package.json"
  assert_failure
  assert_output --regexp "Error.*version"
}

# === COMMIT HISTORY TESTS ===

@test "history: handle no tags gracefully" {
  echo '{"version": "1.0.0"}' > package.json
  git add package.json
  git commit -m "feat: initial commit"

  run semantic_version_bumper "package.json"
  assert_success
}

@test "history: find commits since last tag" {
  git commit --allow-empty -m "initial commit"
  git tag v1.0.0
  git commit --allow-empty -m "feat: feature 1"
  git commit --allow-empty -m "feat: feature 2"

  run get_commits_since_tag "v1.0.0"
  assert_success
  assert_output --regexp "feature 1"
  assert_output --regexp "feature 2"
}

# === VERSION FILE TESTS ===

@test "version_file: detect package.json format" {
  echo '{"version": "1.0.0"}' > package.json
  run get_current_version "package.json"
  assert_success
  assert_output "1.0.0"
}

@test "version_file: detect version.txt format" {
  echo "1.0.0" > version.txt
  run get_current_version "version.txt"
  assert_success
  assert_output "1.0.0"
}

# Helper assertions
assert_success() {
  if [[ $status -ne 0 ]]; then
    echo "Expected success but got exit code $status"
    echo "Output: $output"
    return 1
  fi
}

assert_failure() {
  if [[ $status -eq 0 ]]; then
    echo "Expected failure but got exit code 0"
    echo "Output: $output"
    return 1
  fi
}

assert_output() {
  if [[ -z "$1" ]]; then
    if [[ -n "$output" ]]; then
      echo "Expected empty output but got: $output"
      return 1
    fi
  elif [[ "$1" == "--regexp" ]]; then
    if ! [[ "$output" =~ $2 ]]; then
      echo "Output does not match pattern: $2"
      echo "Got: $output"
      return 1
    fi
  else
    if [[ "$output" != "$1" ]]; then
      echo "Expected output: $1"
      echo "Got: $output"
      return 1
    fi
  fi
}
