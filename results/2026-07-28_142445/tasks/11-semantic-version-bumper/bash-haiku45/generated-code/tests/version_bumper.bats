#!/usr/bin/env bats

# Script path
SCRIPT_PATH="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../semver-bumper.sh"

setup() {
  export TEMP_DIR=$(mktemp -d)
  export PROJECT_DIR="$TEMP_DIR/project"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# Helper: create a git repo with commits
setup_git_repo() {
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"
}

# Helper: add a commit with message
add_commit() {
  local message="$1"
  echo "change-$(date +%s)" >> file.txt
  git add file.txt
  git commit -m "$message"
}

# Test 1: Parse version from package.json
@test "parse version from package.json" {
  cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

  local version=$($SCRIPT_PATH parse-version)
  [ "$version" = "1.0.0" ]
}

# Test 2: Parse version from VERSION file
@test "parse version from VERSION file" {
  echo "2.3.4" > VERSION

  local version=$($SCRIPT_PATH parse-version)
  [ "$version" = "2.3.4" ]
}

# Test 3: Bump patch version for fix commits
@test "bump patch version for fix commits" {
  echo "1.0.0" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "initial"

  add_commit "fix: correct typo in docs"
  add_commit "fix: handle edge case"

  local new_version=$($SCRIPT_PATH calculate-next-version 1.0.0)
  [ "$new_version" = "1.0.2" ]
}

# Test 4: Bump minor version for feat commits
@test "bump minor version for feat commits" {
  echo "1.0.0" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "initial"

  add_commit "feat: add new feature"

  local new_version=$($SCRIPT_PATH calculate-next-version 1.0.0)
  [ "$new_version" = "1.1.0" ]
}

# Test 5: Bump major version for breaking changes
@test "bump major version for breaking change" {
  echo "1.0.0" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "initial"

  add_commit "feat: new API

BREAKING CHANGE: old API removed"

  local new_version=$($SCRIPT_PATH calculate-next-version 1.0.0)
  [ "$new_version" = "2.0.0" ]
}

# Test 6: Update VERSION file
@test "update VERSION file with new version" {
  echo "1.0.0" > VERSION

  $SCRIPT_PATH update-version VERSION 1.1.0

  [ "$(cat VERSION)" = "1.1.0" ]
}

# Test 7: Update package.json version
@test "update package.json with new version" {
  cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

  $SCRIPT_PATH update-version package.json 1.1.0

  grep -q '"version": "1.1.0"' package.json
}

# Test 8: Generate changelog entry
@test "generate changelog entry from commits" {
  echo "1.0.0" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "v1.0.0"

  add_commit "feat: add authentication"
  add_commit "fix: correct validation logic"
  add_commit "docs: update README"

  local changelog=$($SCRIPT_PATH generate-changelog 1.0.0 1.1.0)

  echo "$changelog" | grep -q "add authentication"
  echo "$changelog" | grep -q "correct validation"
}

# Test 9: No version bump for docs-only changes
@test "no version bump for docs-only changes" {
  echo "1.0.0" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "initial"

  add_commit "docs: update README"
  add_commit "docs: add examples"

  local new_version=$($SCRIPT_PATH calculate-next-version 1.0.0)
  [ "$new_version" = "1.0.0" ]
}

# Test 10: Complex version bump (multiple commit types)
@test "handle multiple commit types correctly" {
  echo "1.2.3" > VERSION
  setup_git_repo
  git add VERSION
  git commit -m "initial"

  add_commit "fix: bug fix"
  add_commit "feat: new feature"
  add_commit "fix: another fix"

  local new_version=$($SCRIPT_PATH calculate-next-version 1.2.3)
  [ "$new_version" = "1.3.0" ]
}
