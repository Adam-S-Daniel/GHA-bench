#!/usr/bin/env bats
# Integration tests for semantic version bumper

load test_helper

source ./semantic-version-bumper.sh

setup() {
  # Create test project with git repo
  export TEST_REPO="$TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create version file
  echo "1.0.0" > version.txt
  git add version.txt
  git commit -m "Initial commit with version 1.0.0"
}

teardown() {
  cd /
}

@test "integration: full workflow with fix commit" {
  # Create a fix commit
  git commit --allow-empty -m "fix: correct calculation error"

  # Get old version
  old_version=$(parse_version "$TEST_REPO/version.txt")
  [ "$old_version" = "1.0.0" ]

  # Determine bump type
  bump_type=$(determine_bump "HEAD~1" "HEAD")
  [ "$bump_type" = "patch" ]

  # Calculate new version
  new_version=$(next_version "$old_version" "$bump_type")
  [ "$new_version" = "1.0.1" ]

  # Update version file
  update_version "$TEST_REPO/version.txt" "$new_version"

  # Verify file was updated
  [ "$(cat "$TEST_REPO/version.txt")" = "1.0.1" ]
}

@test "integration: full workflow with feat commit" {
  # Create feature commits
  git commit --allow-empty -m "feat: add new API endpoint"
  git commit --allow-empty -m "fix: handle edge case"

  old_version=$(parse_version "$TEST_REPO/version.txt")
  bump_type=$(determine_bump "HEAD~2" "HEAD")
  [ "$bump_type" = "minor" ]

  new_version=$(next_version "$old_version" "$bump_type")
  [ "$new_version" = "1.1.0" ]

  update_version "$TEST_REPO/version.txt" "$new_version"
  [ "$(cat "$TEST_REPO/version.txt")" = "1.1.0" ]
}

@test "integration: full workflow with breaking change" {
  git commit --allow-empty -m "feat: restructure API

BREAKING CHANGE: old endpoint /api/v1 removed"

  old_version=$(parse_version "$TEST_REPO/version.txt")
  bump_type=$(determine_bump "HEAD~1" "HEAD")
  [ "$bump_type" = "major" ]

  new_version=$(next_version "$old_version" "$bump_type")
  [ "$new_version" = "2.0.0" ]

  update_version "$TEST_REPO/version.txt" "$new_version"
  changelog=$(generate_changelog "HEAD~1" "HEAD")

  [[ "$changelog" =~ "BREAKING CHANGE" ]]
  [[ "$changelog" =~ "restructure API" ]]
}

@test "integration: with package.json instead of version.txt" {
  cd "$TEST_REPO"
  rm version.txt
  cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "description": "test"
}
EOF
  git add package.json
  git rm version.txt 2>/dev/null || true
  git commit -m "Switch to package.json" || true

  git commit --allow-empty -m "feat: new capability"

  old_version=$(parse_version "$TEST_REPO/package.json")
  [ "$old_version" = "1.0.0" ]

  bump_type=$(determine_bump "HEAD~1" "HEAD")
  [ "$bump_type" = "minor" ]

  new_version=$(next_version "$old_version" "$bump_type")
  [ "$new_version" = "1.1.0" ]

  update_version "$TEST_REPO/package.json" "$new_version"

  # Verify version was updated in package.json
  result=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEST_REPO/package.json" | grep -o '[0-9]\.[0-9]\.[0-9]')
  [ "$result" = "1.1.0" ]
}
