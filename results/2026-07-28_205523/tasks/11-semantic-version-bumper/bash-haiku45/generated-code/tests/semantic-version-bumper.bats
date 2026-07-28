#!/usr/bin/env bats
# Test suite for semantic version bumper script

setup() {
  # Create a temporary directory for each test
  export TEST_TEMP_DIR="$(mktemp -d)"
  # Get the directory where bats is running from and use that as the base
  export SCRIPT_DIR="$(pwd)"
  export BUMPER_SCRIPT="${SCRIPT_DIR}/bin/semantic-version-bumper.sh"
}

teardown() {
  # Clean up temporary directory
  rm -rf "$TEST_TEMP_DIR"
}

# Test 1: Parse current version from package.json
@test "Parse current version from package.json" {
  # Create a package.json with a version
  cat > "$TEST_TEMP_DIR/package.json" << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "description": "Test"
}
EOF

  # Run the script to get current version
  result=$("$BUMPER_SCRIPT" --get-current-version "$TEST_TEMP_DIR/package.json")
  [ "$result" = "1.0.0" ]
}

# Test 2: Parse current version from VERSION file
@test "Parse current version from VERSION file" {
  echo "2.5.3" > "$TEST_TEMP_DIR/VERSION"

  result=$("$BUMPER_SCRIPT" --get-current-version "$TEST_TEMP_DIR/VERSION")
  [ "$result" = "2.5.3" ]
}

# Test 3: Determine patch bump from fix commits
@test "Determine patch bump from fix commits" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial commit" >/dev/null 2>&1

  # Create a fix commit
  echo "test2" > file.txt
  git add file.txt
  git commit -m "fix: bug in parser" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --determine-bump "$TEST_TEMP_DIR" "1.0.0")
  [ "$result" = "1.0.1" ]
}

# Test 4: Determine minor bump from feat commits
@test "Determine minor bump from feat commits" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial commit" >/dev/null 2>&1

  # Create a feat commit
  echo "test2" > file.txt
  git add file.txt
  git commit -m "feat: add new parser" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --determine-bump "$TEST_TEMP_DIR" "1.0.0")
  [ "$result" = "1.1.0" ]
}

# Test 5: Determine major bump from breaking changes
@test "Determine major bump from breaking changes" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial commit" >/dev/null 2>&1

  # Create a breaking change commit
  echo "test2" > file.txt
  git add file.txt
  git commit -m "feat!: redesign API" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --determine-bump "$TEST_TEMP_DIR" "1.0.0")
  [ "$result" = "2.0.0" ]
}

# Test 6: Update version in package.json
@test "Update version in package.json" {
  cat > "$TEST_TEMP_DIR/package.json" << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "description": "Test"
}
EOF

  "$BUMPER_SCRIPT" --update-version "$TEST_TEMP_DIR/package.json" "1.1.0"

  result=$(grep -o '"version": "[^"]*"' "$TEST_TEMP_DIR/package.json")
  [ "$result" = '"version": "1.1.0"' ]
}

# Test 7: Update version in VERSION file
@test "Update version in VERSION file" {
  echo "1.0.0" > "$TEST_TEMP_DIR/VERSION"

  "$BUMPER_SCRIPT" --update-version "$TEST_TEMP_DIR/VERSION" "1.0.1"

  content=$(cat "$TEST_TEMP_DIR/VERSION")
  [ "$content" = "1.0.1" ]
}

# Test 8: Generate changelog entry from commits
@test "Generate changelog entry from commits" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create tag for version 1.0.0
  echo "test" > file.txt
  git add file.txt
  git commit -m "Initial commit" >/dev/null 2>&1
  git tag v1.0.0 >/dev/null 2>&1

  # Create new commits
  echo "test2" > file.txt
  git add file.txt
  git commit -m "feat: add new feature" >/dev/null 2>&1

  echo "test3" > file.txt
  git add file.txt
  git commit -m "fix: correct behavior" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --generate-changelog "$TEST_TEMP_DIR" "v1.0.0" "1.1.0")

  # Should contain the commits
  [[ "$result" == *"feat: add new feature"* ]]
  [[ "$result" == *"fix: correct behavior"* ]]
}

# Test 9: Full integration test with patch version
@test "Full integration: patch version bump" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit with version file
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -m "Initial commit" >/dev/null 2>&1
  git tag v1.0.0 >/dev/null 2>&1

  # Create a fix commit
  echo "fix" > file.txt
  git add file.txt
  git commit -m "fix: resolve issue" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --full-run "$TEST_TEMP_DIR" "VERSION" "v")

  [ "$result" = "1.0.1" ]
  [ "$(cat "$TEST_TEMP_DIR/VERSION")" = "1.0.1" ]
}

# Test 10: Full integration test with minor version
@test "Full integration: minor version bump" {
  cd "$TEST_TEMP_DIR"
  git init >/dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit with version file
  echo "1.5.0" > VERSION
  git add VERSION
  git commit -m "Initial commit" >/dev/null 2>&1
  git tag v1.5.0 >/dev/null 2>&1

  # Create a feat commit
  echo "feat" > file.txt
  git add file.txt
  git commit -m "feat: new capability" >/dev/null 2>&1

  result=$("$BUMPER_SCRIPT" --full-run "$TEST_TEMP_DIR" "VERSION" "v")

  [ "$result" = "1.6.0" ]
  [ "$(cat "$TEST_TEMP_DIR/VERSION")" = "1.6.0" ]
}

# Test 11: Error handling for invalid version format
@test "Error handling for invalid version format" {
  cat > "$TEST_TEMP_DIR/package.json" << 'EOF'
{
  "version": "invalid"
}
EOF

  run "$BUMPER_SCRIPT" --get-current-version "$TEST_TEMP_DIR/package.json"
  [ $status -ne 0 ]
}

# Test 12: Error handling for missing version file
@test "Error handling for missing version file" {
  run "$BUMPER_SCRIPT" --get-current-version "$TEST_TEMP_DIR/nonexistent.json"
  [ $status -ne 0 ]
}
