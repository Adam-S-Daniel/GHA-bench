#!/usr/bin/env bats
# Test suite for changelog generation

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

@test "generate_changelog: formats fix commits" {
  git commit --allow-empty -m "fix: handle null pointer exception"

  result=$(generate_changelog "HEAD~1" "HEAD")

  [[ "$result" =~ "- handle null pointer exception" ]]
}

@test "generate_changelog: formats feat commits" {
  git commit --allow-empty -m "feat: add support for new API endpoint"

  result=$(generate_changelog "HEAD~1" "HEAD")

  [[ "$result" =~ "- add support for new API endpoint" ]]
}

@test "generate_changelog: includes breaking change notices" {
  git commit --allow-empty -m "feat: restructure configuration

BREAKING CHANGE: old config format no longer supported"

  result=$(generate_changelog "HEAD~1" "HEAD")

  [[ "$result" =~ "BREAKING CHANGE" ]]
}

@test "generate_changelog: skips non-conventional commits" {
  git commit --allow-empty -m "random update"

  result=$(generate_changelog "HEAD~1" "HEAD")

  [[ ! "$result" =~ "random update" ]]
}

@test "generate_changelog: multiple commits in order" {
  git commit --allow-empty -m "fix: bug 1"
  git commit --allow-empty -m "feat: feature 1"
  git commit --allow-empty -m "fix: bug 2"

  result=$(generate_changelog "HEAD~3" "HEAD")

  [[ "$result" =~ "bug 1" ]]
  [[ "$result" =~ "feature 1" ]]
  [[ "$result" =~ "bug 2" ]]
}
