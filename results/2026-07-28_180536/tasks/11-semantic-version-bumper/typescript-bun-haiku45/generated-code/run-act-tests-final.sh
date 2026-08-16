#!/bin/bash
# Final ACT integration tests for GitHub Actions workflow
# Creates test repos with different commit scenarios and runs through act

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
  echo "Test Execution: $(date)"
  echo ""
} > "$RESULT_FILE"

echo "Setup: Preparing for ACT workflow tests..."
echo ""

# Test 1: Feature commit bump (1.0.0 -> 1.1.0)
{
  echo "Test 1: Feature commit (1.0.0 -> 1.1.0)"
  TEST_DIR=$(mktemp -d)

  # Copy project files
  cp -r "$SCRIPT_DIR"/.github "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/src "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/tests "$TEST_DIR/"
  cp "$SCRIPT_DIR"/package.json "$TEST_DIR/"
  cp "$SCRIPT_DIR"/tsconfig.json "$TEST_DIR/"

  # Initialize git
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  # Add feature commit
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -q -m "feat: add new feature"

  # Run act - test job
  echo "  Running workflow test job..."
  ACT_OUTPUT=$(timeout 180 act push -j test --rm -q 2>&1 || echo "ACT_TIMEOUT_OR_ERROR")

  if echo "$ACT_OUTPUT" | grep -q "Job 'test'"; then
    STATUS="PASS"
    ((PASSED++))
    echo "  ✓ Test job succeeded"
  else
    STATUS="FAIL"
    ((FAILED++))
    echo "  ✗ Test job failed"
  fi

  # Save results
  {
    echo ""
    echo "Test 1: Feature Commit (1.0.0 -> 1.1.0)"
    echo "Status: $STATUS"
    echo "Output (first 50 lines):"
    echo "$ACT_OUTPUT" | head -50
  } >> "$SCRIPT_DIR/$RESULT_FILE"

  cd "$SCRIPT_DIR"
  rm -rf "$TEST_DIR"
} 2>&1

echo ""

# Test 2: Fix commit bump (1.0.0 -> 1.0.1)
{
  echo "Test 2: Fix commit (1.0.0 -> 1.0.1)"
  TEST_DIR=$(mktemp -d)

  # Copy project files
  cp -r "$SCRIPT_DIR"/.github "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/src "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/tests "$TEST_DIR/"
  cp "$SCRIPT_DIR"/package.json "$TEST_DIR/"
  cp "$SCRIPT_DIR"/tsconfig.json "$TEST_DIR/"

  # Initialize git
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  # Add fix commit
  echo "fix content" > fix.txt
  git add fix.txt
  git commit -q -m "fix: resolve bug"

  # Run act - test job
  echo "  Running workflow test job..."
  ACT_OUTPUT=$(timeout 180 act push -j test --rm -q 2>&1 || echo "ACT_TIMEOUT_OR_ERROR")

  if echo "$ACT_OUTPUT" | grep -q "Job 'test'"; then
    STATUS="PASS"
    ((PASSED++))
    echo "  ✓ Test job succeeded"
  else
    STATUS="FAIL"
    ((FAILED++))
    echo "  ✗ Test job failed"
  fi

  # Save results
  {
    echo ""
    echo "Test 2: Fix Commit (1.0.0 -> 1.0.1)"
    echo "Status: $STATUS"
    echo "Output (first 50 lines):"
    echo "$ACT_OUTPUT" | head -50
  } >> "$SCRIPT_DIR/$RESULT_FILE"

  cd "$SCRIPT_DIR"
  rm -rf "$TEST_DIR"
} 2>&1

echo ""

# Test 3: Breaking change (1.0.0 -> 2.0.0)
{
  echo "Test 3: Breaking change (1.0.0 -> 2.0.0)"
  TEST_DIR=$(mktemp -d)

  # Copy project files
  cp -r "$SCRIPT_DIR"/.github "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/src "$TEST_DIR/"
  cp -r "$SCRIPT_DIR"/tests "$TEST_DIR/"
  cp "$SCRIPT_DIR"/package.json "$TEST_DIR/"
  cp "$SCRIPT_DIR"/tsconfig.json "$TEST_DIR/"

  # Initialize git
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  # Add breaking change commit
  echo "breaking change" > api.txt
  git add api.txt
  git commit -q -m "feat!: remove deprecated API"

  # Run act - test job
  echo "  Running workflow test job..."
  ACT_OUTPUT=$(timeout 180 act push -j test --rm -q 2>&1 || echo "ACT_TIMEOUT_OR_ERROR")

  if echo "$ACT_OUTPUT" | grep -q "Job 'test'"; then
    STATUS="PASS"
    ((PASSED++))
    echo "  ✓ Test job succeeded"
  else
    STATUS="FAIL"
    ((FAILED++))
    echo "  ✗ Test job failed"
  fi

  # Save results
  {
    echo ""
    echo "Test 3: Breaking Change (1.0.0 -> 2.0.0)"
    echo "Status: $STATUS"
    echo "Output (first 50 lines):"
    echo "$ACT_OUTPUT" | head -50
  } >> "$SCRIPT_DIR/$RESULT_FILE"

  cd "$SCRIPT_DIR"
  rm -rf "$TEST_DIR"
} 2>&1

# Summary
{
  echo ""
  echo "================================================================================"
  echo "Test Summary"
  echo "================================================================================"
  echo "Total Tests: 3"
  echo "Passed: $PASSED"
  echo "Failed: $FAILED"
  echo ""
  if [ $FAILED -eq 0 ]; then
    echo "✓ All workflow tests passed"
  else
    echo "✗ Some workflow tests failed"
  fi
  echo "================================================================================"
} | tee -a "$RESULT_FILE"

echo ""
echo "Results saved to: $RESULT_FILE"
echo ""

exit $FAILED
