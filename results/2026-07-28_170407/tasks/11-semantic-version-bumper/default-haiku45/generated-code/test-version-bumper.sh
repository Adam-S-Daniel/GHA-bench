#!/bin/bash

# Test suite for semantic version bumper using TDD methodology

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_PATH="/home/user/GHA-bench/workspaces/2026-07-28_170407/11-semantic-version-bumper/default-haiku45/version-bumper.sh"

assert_equals() {
  local expected="$1" actual="$2" test_name="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "${GREEN}✓${NC} $test_name"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $test_name"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    ((TESTS_FAILED++))
  fi
}

# Test 1: Parse version from package.json
test1_parse_json() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"

  cat > package.json << 'EOF'
{"name":"test","version":"1.0.0"}
EOF

  local result=$("$SCRIPT_PATH" --parse-version package.json 2>/dev/null)
  assert_equals "1.0.0" "$result" "Parse version from package.json"
  rm -rf "$tmpdir"
}

# Test 2: Parse version from VERSION file
test2_parse_version_file() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  echo "2.3.5" > VERSION

  local result=$("$SCRIPT_PATH" --parse-version VERSION 2>/dev/null)
  assert_equals "2.3.5" "$result" "Parse version from VERSION file"
  rm -rf "$tmpdir"
}

# Test 3: Update version in plain text file
test3_update_version() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  echo "1.0.0" > VERSION

  "$SCRIPT_PATH" --update-version VERSION "1.0.1" 2>/dev/null
  local result=$(cat VERSION)
  assert_equals "1.0.1" "$result" "Update version in VERSION file"
  rm -rf "$tmpdir"
}

# Test 4: Analyze commits - patch bump (fix:)
test4_patch_bump() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  echo "1.0.0" > VERSION
  git add VERSION
  git commit -q -m "Initial"
  git commit -q --allow-empty -m "fix: typo"

  local result=$("$SCRIPT_PATH" --next-version VERSION 2>/dev/null)
  assert_equals "1.0.1" "$result" "Patch bump from fix commit"
  rm -rf "$tmpdir"
}

# Test 5: Analyze commits - minor bump (feat:)
test5_minor_bump() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  echo "1.0.0" > VERSION
  git add VERSION
  git commit -q -m "Initial"
  git commit -q --allow-empty -m "feat: new feature"

  local result=$("$SCRIPT_PATH" --next-version VERSION 2>/dev/null)
  assert_equals "1.1.0" "$result" "Minor bump from feat commit"
  rm -rf "$tmpdir"
}

# Test 6: Analyze commits - major bump (feat!:)
test6_major_bump() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  echo "1.5.3" > VERSION
  git add VERSION
  git commit -q -m "Initial"
  git commit -q --allow-empty -m "feat!: breaking change"

  local result=$("$SCRIPT_PATH" --next-version VERSION 2>/dev/null)
  assert_equals "2.0.0" "$result" "Major bump from breaking change"
  rm -rf "$tmpdir"
}

# Test 7: Generate changelog
test7_changelog() {
  local tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  git commit -q --allow-empty -m "Initial"
  git commit -q --allow-empty -m "fix: parser bug"
  git commit -q --allow-empty -m "feat: markdown support"

  local result=$("$SCRIPT_PATH" --changelog-from-commits 2>/dev/null)
  if echo "$result" | grep -q "Bug Fixes"; then
    echo -e "${GREEN}✓${NC} Generate changelog from commits"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} Generate changelog from commits"
    echo "  Output: $result"
    ((TESTS_FAILED++))
  fi
  rm -rf "$tmpdir"
}

echo "Running semantic version bumper tests..."
echo "========================================="
test1_parse_json
test2_parse_version_file
test3_update_version
test4_patch_bump
test5_minor_bump
test6_major_bump
test7_changelog
echo "========================================="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ]
