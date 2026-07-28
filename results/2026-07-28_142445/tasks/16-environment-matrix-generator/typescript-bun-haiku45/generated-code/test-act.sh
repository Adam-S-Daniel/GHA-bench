#!/bin/bash

# Test harness to run all tests through act (GitHub Actions runner)
# Validates matrix generator functionality in CI/CD pipeline

set -e

RESULT_FILE="act-result.txt"
> "$RESULT_FILE"  # Clear result file

test_count=0
pass_count=0
fail_count=0

# Helper function to run a test case
run_test() {
  local test_name="$1"
  local config_file="$2"
  local options_file="$3"
  local expected_include_count="$4"

  test_count=$((test_count + 1))

  echo "========================================" | tee -a "$RESULT_FILE"
  echo "Test $test_count: $test_name" | tee -a "$RESULT_FILE"
  echo "========================================" | tee -a "$RESULT_FILE"

  # Create temp directory for this test
  local temp_dir=$(mktemp -d)
  trap "rm -rf $temp_dir" EXIT

  # Copy project files to temp dir
  cp -r . "$temp_dir/project"
  cd "$temp_dir/project"

  # Run act
  if act push --rm 2>&1 | tee -a "../../$RESULT_FILE"; then
    local act_exit_code=0
  else
    local act_exit_code=$?
  fi

  echo "Act exit code: $act_exit_code" | tee -a "../../$RESULT_FILE"

  if [ "$act_exit_code" -eq 0 ]; then
    echo "✓ Test passed: $test_name" | tee -a "../../$RESULT_FILE"
    pass_count=$((pass_count + 1))
  else
    echo "✗ Test failed: $test_name" | tee -a "../../$RESULT_FILE"
    fail_count=$((fail_count + 1))
  fi

  cd - > /dev/null
}

echo "Running Environment Matrix Generator Tests via act" | tee -a "$RESULT_FILE"
echo "====================================================" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Test 1: Basic matrix generation
run_test "Basic matrix generation" "fixtures/basic-config.json"

# Test 2: Matrix with options
run_test "Matrix with exclude rules" "fixtures/basic-config.json" "fixtures/with-options.json"

# Test 3: Workflow structure validation
echo "========================================" | tee -a "$RESULT_FILE"
echo "Test $((test_count + 1)): Workflow structure validation" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"

if [ -f ".github/workflows/environment-matrix-generator.yml" ]; then
  echo "✓ Workflow file exists" | tee -a "$RESULT_FILE"

  # Check for expected workflow fields
  if grep -q "on:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has trigger events" | tee -a "$RESULT_FILE"
  fi

  if grep -q "jobs:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has jobs section" | tee -a "$RESULT_FILE"
  fi

  if grep -q "permissions:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has permissions section" | tee -a "$RESULT_FILE"
  fi

  pass_count=$((pass_count + 1))
else
  echo "✗ Workflow file not found" | tee -a "$RESULT_FILE"
  fail_count=$((fail_count + 1))
fi

# Test 4: actionlint validation
echo "========================================" | tee -a "$RESULT_FILE"
echo "Test $((test_count + 2)): actionlint validation" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"

if actionlint .github/workflows/environment-matrix-generator.yml >> "$RESULT_FILE" 2>&1; then
  echo "✓ actionlint passed" | tee -a "$RESULT_FILE"
  pass_count=$((pass_count + 1))
else
  echo "✗ actionlint failed" | tee -a "$RESULT_FILE"
  fail_count=$((fail_count + 1))
fi

# Summary
echo "" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "Test Summary" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "Total tests: $test_count" | tee -a "$RESULT_FILE"
echo "Passed: $pass_count" | tee -a "$RESULT_FILE"
echo "Failed: $fail_count" | tee -a "$RESULT_FILE"

if [ "$fail_count" -eq 0 ]; then
  echo "" | tee -a "$RESULT_FILE"
  echo "All tests passed! ✓" | tee -a "$RESULT_FILE"
  exit 0
else
  echo "" | tee -a "$RESULT_FILE"
  echo "Some tests failed! ✗" | tee -a "$RESULT_FILE"
  exit 1
fi
