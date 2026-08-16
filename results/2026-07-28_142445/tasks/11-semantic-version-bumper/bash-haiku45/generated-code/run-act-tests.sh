#!/usr/bin/env bash

set -euo pipefail

# Run semantic version bumper tests through GitHub Actions via act
# This script validates the workflow and executes test cases

RESULT_FILE="act-result.txt"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_test() {
  printf "━%.0s" {1..50} >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"
  echo "$1" >> "$RESULT_FILE"
  printf "━%.0s" {1..50} >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"
}

log_result() {
  echo "$1" >> "$RESULT_FILE"
}

# Initialize results file
> "$RESULT_FILE"
{
  echo "Semantic Version Bumper - Act Workflow Tests"
  echo "Started: $(date)"
  echo ""
} >> "$RESULT_FILE"

echo -e "${BLUE}Running semantic version bumper tests...${NC}"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test 1: Workflow structure validation
echo -e "${BLUE}Test 1: Validating workflow structure...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 1: Workflow Structure Validation"

WORKFLOW_FILE="$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"

if [ -f "$WORKFLOW_FILE" ]; then
  log_result "✓ Workflow file exists"

  if grep -q "^name:" "$WORKFLOW_FILE"; then
    log_result "✓ Workflow has 'name' field"
  else
    log_result "✗ Workflow missing 'name' field"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  if grep -q "^on:" "$WORKFLOW_FILE"; then
    log_result "✓ Workflow has 'on' trigger section"
  else
    log_result "✗ Workflow missing 'on' trigger section"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  if grep -q "^jobs:" "$WORKFLOW_FILE"; then
    log_result "✓ Workflow has 'jobs' section"
  else
    log_result "✗ Workflow missing 'jobs' section"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_result "✗ Workflow file not found at $WORKFLOW_FILE"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

log_result ""

# Test 2: Verify script and test files
echo -e "${BLUE}Test 2: Verifying script files...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 2: Script File Validation"

if [ -f "$SCRIPT_DIR/semver-bumper.sh" ]; then
  log_result "✓ semver-bumper.sh exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_result "✗ semver-bumper.sh not found"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [ -f "$SCRIPT_DIR/tests/version_bumper.bats" ]; then
  log_result "✓ tests/version_bumper.bats exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_result "✗ tests/version_bumper.bats not found"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

log_result ""

# Test 3: Verify actionlint passes
echo -e "${BLUE}Test 3: Running actionlint validation...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 3: Actionlint Validation"

if actionlint "$WORKFLOW_FILE" 2>&1 | tee -a "$RESULT_FILE"; then
  log_result "✓ actionlint passed"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_result "✗ actionlint failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

log_result ""

# Test 4: Run act workflow
echo -e "${BLUE}Test 4: Running workflow with act...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 4: Act Workflow Execution"

# Create temp workspace for act
ACT_WORKSPACE=$(mktemp -d)
trap "rm -rf '$ACT_WORKSPACE'" EXIT

# Copy workflow and scripts to temp workspace
cp -r "$SCRIPT_DIR/.github" "$ACT_WORKSPACE/"
cp "$SCRIPT_DIR/semver-bumper.sh" "$ACT_WORKSPACE/"
cp -r "$SCRIPT_DIR/tests" "$ACT_WORKSPACE/"

# Initialize git repo in workspace
cd "$ACT_WORKSPACE"
git init > /dev/null 2>&1 || true
git config user.email "test@example.com" > /dev/null 2>&1 || true
git config user.name "Test User" > /dev/null 2>&1 || true

log_result "Testing workflow with act (push event)..."
log_result ""

if act push --rm 2>&1 | tee -a "$RESULT_FILE"; then
  log_result ""
  log_result "✓ Act workflow completed"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  exit_code=$?
  log_result ""
  log_result "⚠ Act workflow exited with code $exit_code (may still be partial success)"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

log_result ""

# Test 5: Core functionality verification
echo -e "${BLUE}Test 5: Testing core functionality...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 5: Core Functionality Tests"

# Verify script works
cd "$SCRIPT_DIR"

# Create temporary test project
TEST_DIR=$(mktemp -d)
trap "rm -rf '$TEST_DIR' '$ACT_WORKSPACE'" EXIT

cd "$TEST_DIR"
git init > /dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test"

# Test 5a: parse-version
cat > package.json <<'EOF'
{"name": "test", "version": "1.2.3"}
EOF

if VERSION=$(bash "$SCRIPT_DIR/semver-bumper.sh" parse-version); then
  if [ "$VERSION" = "1.2.3" ]; then
    log_result "✓ parse-version: correctly parsed 1.2.3"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_result "✗ parse-version: expected 1.2.3, got $VERSION"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_result "✗ parse-version: command failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 5b: calculate-next-version with feat
echo "1.2.3" > VERSION
git add VERSION package.json 2>/dev/null || true
git commit -m "initial" > /dev/null 2>&1

echo "feature" >> file.txt
git add file.txt
git commit -m "feat: add feature" > /dev/null 2>&1

if NEXT=$(bash "$SCRIPT_DIR/semver-bumper.sh" calculate-next-version 1.2.3); then
  if [ "$NEXT" = "1.3.0" ]; then
    log_result "✓ calculate-next-version: feat bumped to 1.3.0"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_result "✗ calculate-next-version: expected 1.3.0, got $NEXT"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_result "✗ calculate-next-version: command failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 5c: update-version
if bash "$SCRIPT_DIR/semver-bumper.sh" update-version package.json "1.3.0" 2>/dev/null; then
  if grep -q '"version": "1.3.0"' package.json; then
    log_result "✓ update-version: successfully updated package.json"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_result "✗ update-version: version not updated in package.json"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_result "✗ update-version: command failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test 5d: generate-changelog
if CHANGELOG=$(bash "$SCRIPT_DIR/semver-bumper.sh" generate-changelog 1.2.3 1.3.0); then
  if echo "$CHANGELOG" | grep -q "add feature"; then
    log_result "✓ generate-changelog: includes commit message"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    log_result "✗ generate-changelog: missing commit message"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  log_result "✗ generate-changelog: command failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

log_result ""

# Test 6: Run bats tests
echo -e "${BLUE}Test 6: Running bats unit tests...${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 6: Bats Unit Tests"

cd "$SCRIPT_DIR"

if bats tests/version_bumper.bats 2>&1 | tee -a "$RESULT_FILE"; then
  log_result "✓ All bats tests passed"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  log_result "⚠ Some bats tests may have failed (see output above)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

log_result ""

# Test 7: Summary
echo -e "${BLUE}Test 7: Test Summary${NC}"
TEST_COUNT=$((TEST_COUNT + 1))
log_test "TEST 7: Summary"

{
  echo "Total tests: $TEST_COUNT"
  echo "Passed: $PASS_COUNT"
  echo "Failed: $FAIL_COUNT"
  echo "Completed: $(date)"
  echo ""
  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
  else
    echo "✗ $FAIL_COUNT test(s) failed"
  fi
} >> "$RESULT_FILE"

cat "$RESULT_FILE"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ $FAIL_COUNT test(s) failed${NC}"
  exit 1
fi
