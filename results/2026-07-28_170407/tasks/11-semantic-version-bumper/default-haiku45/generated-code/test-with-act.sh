#!/bin/bash

# Comprehensive test using act to run the GitHub Actions workflow

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="$SCRIPT_DIR/act-result.txt"
TEMP_DIR=""
TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

setup_test_repo() {
  local initial_version="$1"
  local commit_msg="$2"

  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"

  # Initialize git repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test User"

  # Setup directory structure
  mkdir -p .github/workflows

  # Copy workflow and script
  cp "$SCRIPT_DIR/version-bumper.sh" .
  chmod +x version-bumper.sh
  cp "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" .github/workflows/

  # Create package.json
  cat > package.json << EOF
{
  "name": "test-app",
  "version": "$initial_version"
}
EOF

  # Initial commit
  git add .
  git commit -q -m "Initial commit with version $initial_version"

  # Add feature/fix commit
  git commit -q --allow-empty -m "$commit_msg"
}

run_act_test() {
  local test_name="$1"
  local initial_version="$2"
  local commit_msg="$3"
  local expected_version="$4"

  echo ""
  echo "=== TEST: $test_name ==="
  echo "Initial: $initial_version | Commit: $commit_msg | Expected: $expected_version"

  setup_test_repo "$initial_version" "$commit_msg"

  # Run workflow
  echo "Running act push..."
  local act_output
  if act_output=$(act push --rm -j version-bump 2>&1); then
    echo -e "${GREEN}✓${NC} Workflow executed successfully"
    ((TESTS_PASSED++))

    # Check for expected version in output
    if echo "$act_output" | grep -q "Next version: $expected_version"; then
      echo -e "${GREEN}✓${NC} Detected expected version: $expected_version"
      ((TESTS_PASSED++))
      echo "$act_output" | grep "Next version:"
    else
      echo -e "${RED}✗${NC} Did not detect version $expected_version"
      ((TESTS_FAILED++))
      echo "Output:"
      echo "$act_output" | grep -i "version\|error" || echo "(no version info found)"
    fi

    # Check for "Job succeeded" or similar success indicator
    if echo "$act_output" | grep -q "Job 'version-bump' completed"; then
      echo -e "${GREEN}✓${NC} Job completed successfully"
      ((TESTS_PASSED++))
    else
      echo -e "${YELLOW}⚠${NC}  Job completion status unclear"
    fi
  else
    echo -e "${RED}✗${NC} Workflow execution failed"
    ((TESTS_FAILED++))
    echo "Error output:"
    echo "$act_output" | tail -20
  fi

  cd "$SCRIPT_DIR"
}

# Main test runner
echo "====================================================="
echo "GitHub Actions Workflow Tests (with act)"
echo "====================================================="

# Save result header
> "$RESULTS_FILE"
echo "Semantic Version Bumper - Act Test Results" | tee -a "$RESULTS_FILE"
echo "==========================================" | tee -a "$RESULTS_FILE"

# Test 1: Patch bump
echo "" | tee -a "$RESULTS_FILE"
run_act_test "Patch Bump (fix commit)" "1.0.0" "fix: correct typo" "1.0.1"
echo "" | tee -a "$RESULTS_FILE"

# Test 2: Minor bump
echo "" | tee -a "$RESULTS_FILE"
run_act_test "Minor Bump (feat commit)" "2.0.0" "feat: add authentication" "2.1.0"
echo "" | tee -a "$RESULTS_FILE"

# Test 3: Major bump
echo "" | tee -a "$RESULTS_FILE"
run_act_test "Major Bump (breaking change)" "1.5.3" "feat!: redesign API" "2.0.0"
echo "" | tee -a "$RESULTS_FILE"

# Summary
echo "====================================================="
echo "Test Summary"
echo "====================================================="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""
echo "Detailed results saved to: $RESULTS_FILE"

# Append summary to results file
{
  echo ""
  echo "====================================================="
  echo "Test Summary"
  echo "Tests passed: $TESTS_PASSED"
  echo "Tests failed: $TESTS_FAILED"
} >> "$RESULTS_FILE"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All workflow tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
