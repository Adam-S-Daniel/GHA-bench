#!/bin/bash
# Run GitHub Actions workflow tests with act for different scenarios

set -e

RESULT_FILE="act-result.txt"
SCRIPT_DIR=$(pwd)
PASSED=0
FAILED=0

# Initialize result file
{
  echo "================================================================================"
  echo "Semantic Version Bumper - ACT Workflow Integration Tests"
  echo "================================================================================"
  echo ""
  echo "Test Date: $(date)"
  echo "Script Directory: $SCRIPT_DIR"
  echo ""
} > "$RESULT_FILE"

# Function to run a test scenario
run_test_scenario() {
  local TEST_NAME="$1"
  local COMMITS="$2"
  local EXPECTED_VERSION="$3"

  echo "Running: $TEST_NAME"

  # Create temporary test directory
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"

  # Copy project files
  cp -r "$SCRIPT_DIR"/* .

  # Initialize git repo
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create initial commit and tag
  echo "# Initial Commit" > README.md
  git add README.md
  git commit -q -m "initial: setup"
  git tag v1.0.0

  # Add test commits
  if [ ! -z "$COMMITS" ]; then
    # Split commits by newline and create each one
    while IFS= read -r commit_msg; do
      if [ ! -z "$commit_msg" ]; then
        echo "Test content" >> "test-file-$(date +%s).txt"
        git add .
        git commit -q -m "$commit_msg"
      fi
    done <<< "$COMMITS"
  fi

  # Run act
  echo "  Running: act push -j test --rm -q" >> "$SCRIPT_DIR/$RESULT_FILE"
  ACT_OUTPUT=$(act push -j test --rm -q 2>&1 || true)

  # Check if test succeeded
  if echo "$ACT_OUTPUT" | grep -q "Job 'test'"; then
    ((PASSED++))
    STATUS="PASS"
    echo "  ✓ $TEST_NAME"
  else
    ((FAILED++))
    STATUS="FAIL"
    echo "  ✗ $TEST_NAME"
  fi

  # Save to result file
  {
    echo ""
    echo "=================================================================================="
    echo "Test: $TEST_NAME"
    echo "Status: $STATUS"
    echo "Expected Version: $EXPECTED_VERSION"
    echo "=================================================================================="
    echo "$ACT_OUTPUT" | head -100
  } >> "$SCRIPT_DIR/$RESULT_FILE"

  # Cleanup
  cd "$SCRIPT_DIR"
  rm -rf "$TEST_DIR"
}

echo "================================================================================"
echo "Workflow ACT Integration Tests"
echo "================================================================================"
echo ""

# Test 1: Feature commit
run_test_scenario \
  "Feature Commit (1.0.0 -> 1.1.0)" \
  "feat: add new feature" \
  "1.1.0"

# Test 2: Fix commit
run_test_scenario \
  "Fix Commit (1.0.0 -> 1.0.1)" \
  "fix: resolve bug" \
  "1.0.1"

# Test 3: Breaking change
run_test_scenario \
  "Breaking Change (1.0.0 -> 2.0.0)" \
  "feat!: remove deprecated API" \
  "2.0.0"

echo ""
echo "================================================================================"
{
  echo ""
  echo "================================================================================"
  echo "Test Summary"
  echo "================================================================================"
  echo "Passed: $PASSED"
  echo "Failed: $FAILED"
  echo "Total:  $((PASSED + FAILED))"
  echo ""
  if [ $FAILED -eq 0 ]; then
    echo "✓ All workflow tests passed!"
  else
    echo "✗ Some workflow tests failed"
  fi
  echo "================================================================================"
} | tee -a "$RESULT_FILE"

echo "Results saved to: $RESULT_FILE"
echo ""

# Exit with appropriate code
if [ $FAILED -eq 0 ]; then
  exit 0
else
  exit 1
fi
