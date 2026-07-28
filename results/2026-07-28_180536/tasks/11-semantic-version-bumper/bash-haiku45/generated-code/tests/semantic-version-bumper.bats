#!/usr/bin/env bats

# Semantic version bumper test suite
# Uses red/green TDD methodology

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_GIT_DIR="${TEST_TEMP_DIR}/git-repo"
  mkdir -p "${TEST_GIT_DIR}"
  cd "${TEST_GIT_DIR}"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
}

teardown() {
  cd /
  rm -rf "${TEST_TEMP_DIR}"
}

# Test 1: Parse current version from package.json
@test "parse version from package.json" {
  cat > package.json <<'EOF'
{
  "name": "test-app",
  "version": "1.0.0"
}
EOF

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --current-version package.json 2>&1)
  [ "$result" = "1.0.0" ]
}

# Test 2: Parse version from version file
@test "parse version from VERSION file" {
  echo "2.5.3" > VERSION

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --current-version VERSION 2>&1)
  [ "$result" = "2.5.3" ]
}

# Test 3: Bump patch version
@test "bump patch version with fix commits" {
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "initial commit"

  git commit --allow-empty -m "fix: resolve bug in parser"

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --next-version VERSION 2>&1)
  [ "$result" = "1.0.1" ]
}

# Test 4: Bump minor version for feature
@test "bump minor version with feat commits" {
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "initial commit"

  git commit --allow-empty -m "feat: add new validation logic"

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --next-version VERSION 2>&1)
  [ "$result" = "1.1.0" ]
}

# Test 5: Bump major version for breaking change
@test "bump major version with breaking change" {
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "initial commit"

  git commit --allow-empty -m "feat!: remove deprecated API endpoints"

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --next-version VERSION 2>&1)
  [ "$result" = "2.0.0" ]
}

# Test 6: Update version in package.json
@test "update version in package.json" {
  cat > package.json <<'EOF'
{
  "name": "test-app",
  "version": "1.0.0"
}
EOF
  git add package.json
  git commit -m "initial"

  git commit --allow-empty -m "feat: add feature"

  /home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --update package.json >/dev/null 2>&1

  result=$(grep -o '"version": "[^"]*' package.json | cut -d'"' -f4)
  [ "$result" = "1.1.0" ]
}

# Test 7: Generate changelog from commits
@test "generate changelog entry" {
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "initial commit"

  git commit --allow-empty -m "feat: add new feature X"
  git commit --allow-empty -m "fix: correct behavior in module Y"

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --changelog VERSION 2>&1)

  # Changelog should contain new version and commits
  echo "$result" | grep -q "1.1.0"
  echo "$result" | grep -q "add new feature X"
}

# Test 8: Handle no commits since last version
@test "handle no new commits" {
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "version: bump to 1.0.0"

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --next-version VERSION 2>&1)
  [ "$result" = "1.0.0" ]
}

# Test 9: Parse v-prefixed versions
@test "handle v-prefixed versions" {
  echo "v1.2.3" > VERSION

  result=$(/home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --current-version VERSION 2>&1)
  [ "$result" = "1.2.3" ]
}

# Test 10: Error handling for invalid version format
@test "error on invalid version format" {
  echo "not-a-version" > VERSION

  ! /home/user/GHA-bench/workspaces/2026-07-28_180536/11-semantic-version-bumper/bash-haiku45/semantic-version-bumper.sh --current-version VERSION 2>/dev/null
}
