#!/usr/bin/env bats
# Test suite for version bumping based on conventional commits

load test_helper

source ./semantic-version-bumper.sh

setup() {
  # Initialize a test git repository
  export TEST_REPO="$TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "initial" > README.md
  git add README.md
  git commit -m "Initial commit"
}

teardown() {
  cd /
}

@test "determine_bump: returns patch for fix commits" {
  git commit --allow-empty -m "fix: correct spelling in README"

  result=$(determine_bump "HEAD~1" "HEAD")

  [ "$result" = "patch" ]
}

@test "determine_bump: returns minor for feat commits" {
  git commit --allow-empty -m "feat: add new feature"

  result=$(determine_bump "HEAD~1" "HEAD")

  [ "$result" = "minor" ]
}

@test "determine_bump: returns major for breaking changes" {
  git commit --allow-empty -m "feat: restructure API

BREAKING CHANGE: old API no longer supported"

  result=$(determine_bump "HEAD~1" "HEAD")

  [ "$result" = "major" ]
}

@test "determine_bump: prioritizes breaking changes over other types" {
  git commit --allow-empty -m "feat: new feature"
  git commit --allow-empty -m "fix: bug fix

BREAKING CHANGE: some behavior changed"

  result=$(determine_bump "HEAD~2" "HEAD")

  [ "$result" = "major" ]
}

@test "determine_bump: returns minor if feat exists without breaking" {
  git commit --allow-empty -m "fix: bug 1"
  git commit --allow-empty -m "feat: feature 1"
  git commit --allow-empty -m "fix: bug 2"

  result=$(determine_bump "HEAD~3" "HEAD")

  [ "$result" = "minor" ]
}

@test "determine_bump: returns patch if only fixes exist" {
  git commit --allow-empty -m "fix: bug 1"
  git commit --allow-empty -m "fix: bug 2"

  result=$(determine_bump "HEAD~2" "HEAD")

  [ "$result" = "patch" ]
}

@test "determine_bump: handles no conventional commits" {
  git commit --allow-empty -m "random commit message"

  result=$(determine_bump "HEAD~1" "HEAD")

  [ "$result" = "none" ]
}
