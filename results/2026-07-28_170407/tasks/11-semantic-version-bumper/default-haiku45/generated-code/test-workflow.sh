#!/bin/bash

# Test runner for GitHub Actions workflow using act
# This script sets up test fixtures and validates workflow execution

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="$SCRIPT_DIR/act-result.txt"
TESTS_PASSED=0
TESTS_FAILED=0

# Initialize results file
> "$RESULTS_FILE"

log_result() {
  echo "$@" | tee -a "$RESULTS_FILE"
}

run_test() {
  local test_name="$1"
  local initial_version="$2"
  local commit_msg="$3"
  local expected_version="$4"

  log_result ""
  log_result "=== TEST: $test_name ==="
  log_result "Setup: Initial version=$initial_version, Commit: $commit_msg, Expected: $expected_version"

  # Create temporary test directory
  local test_dir=$(mktemp -d)
  cd "$test_dir"

  # Initialize git repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"

  # Copy workflow and script files
  mkdir -p .github/workflows
  cp "$SCRIPT_DIR/version-bumper.sh" .
  cp "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" .github/workflows/

  # Create package.json with initial version
  cat > package.json << EOF
{
  "name": "test-app",
  "version": "$initial_version"
}
EOF

  # Initial commit
  git add .
  git commit -q -m "Initial commit"

  # Add commit with specified message
  git commit -q --allow-empty -m "$commit_msg"

  # Run workflow with act
  log_result "Running act push..."
  if act push --rm -j version-bump >> "$RESULTS_FILE" 2>&1; then
    log_result "✓ act completed successfully"
    ((TESTS_PASSED++))

    # Parse output to verify version
    if grep -q "Next version: $expected_version" "$RESULTS_FILE"; then
      log_result -e "${GREEN}✓${NC} Version correctly detected as $expected_version"
      ((TESTS_PASSED++))
    else
      log_result -e "${RED}✗${NC} Version not detected as $expected_version"
      ((TESTS_FAILED++))
    fi
  else
    log_result -e "${RED}✗${NC} act failed"
    ((TESTS_FAILED++))
  fi

  # Cleanup
  cd /
  rm -rf "$test_dir"
}

echo "Testing Semantic Version Bumper Workflow with act"
echo "=================================================="

# Test 1: Patch bump (fix commit)
run_test "Patch Version Bump" "1.0.0" "fix: correct typo" "1.0.1"

# Test 2: Minor bump (feat commit)
run_test "Minor Version Bump" "1.0.0" "feat: add new feature" "1.1.0"

# Test 3: Major bump (breaking change)
run_test "Major Version Bump" "1.5.3" "feat!: redesign API" "2.0.0"

# Summary
log_result ""
log_result "=================================================="
log_result "Test Summary"
log_result "Tests passed: $TESTS_PASSED"
log_result "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
  log_result -e "${GREEN}All workflow tests passed!${NC}"
  exit 0
else
  log_result -e "${RED}Some tests failed${NC}"
  exit 1
fi
