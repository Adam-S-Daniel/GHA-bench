#!/usr/bin/env bash

# run-act-tests.sh - Run workflow tests through act and capture results
# This script validates that the matrix-generator workflow runs successfully

set -euo pipefail

# Output file for test results
RESULTS_FILE="act-result.txt"

# Function to log test results
log_test() {
  local test_name="$1"
  local status="$2"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $test_name: $status" | tee -a "$RESULTS_FILE"
}

# Function to run a test case
run_test_case() {
  local test_name="$1"
  local fixture_file="$2"

  log_test "$test_name" "STARTING"

  echo "=== Test: $test_name ===" >> "$RESULTS_FILE"
  echo "Fixture: $fixture_file" >> "$RESULTS_FILE"

  if [ ! -f "$fixture_file" ]; then
    log_test "$test_name" "FAILED - fixture not found"
    return 1
  fi

  # Show fixture content
  echo "Configuration:" >> "$RESULTS_FILE"
  cat "$fixture_file" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"

  # Test the matrix generator directly
  echo "Direct test output:" >> "$RESULTS_FILE"
  if output=$(cat "$fixture_file" | ./matrix-generator.sh 2>&1); then
    echo "$output" | jq . >> "$RESULTS_FILE" 2>/dev/null || echo "$output" >> "$RESULTS_FILE"
    log_test "$test_name" "PASSED"
    return 0
  else
    echo "ERROR: $output" >> "$RESULTS_FILE"
    log_test "$test_name" "FAILED"
    return 1
  fi
}

# Initialize results file
echo "Environment Matrix Generator - Act Test Results" > "$RESULTS_FILE"
echo "Generated: $(date)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Check that required tools are available
if ! command -v act &> /dev/null; then
  echo "ERROR: act is not installed. Install it with: brew install act (macOS) or see https://github.com/nektos/act"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not running"
  exit 1
fi

echo "Running matrix generator tests through act..." | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# Test 1: Simple matrix
if run_test_case "Simple Matrix" "fixtures/simple.json"; then
  test_result_1=0
else
  test_result_1=1
fi

# Test 2: Complex matrix
if run_test_case "Complex Matrix" "fixtures/complex.json"; then
  test_result_2=0
else
  test_result_2=1
fi

# Now run the actual GitHub Actions workflow through act
echo "" | tee -a "$RESULTS_FILE"
echo "Running GitHub Actions workflow through act..." | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

if act push --rm -j test -W .github/workflows/environment-matrix-generator.yml 2>&1 | tee -a "$RESULTS_FILE"; then
  act_test_result=0
  log_test "GitHub Actions Workflow" "PASSED"
else
  act_test_result=1
  log_test "GitHub Actions Workflow" "FAILED"
fi

# Validate validation job
if act push --rm -j validate -W .github/workflows/environment-matrix-generator.yml 2>&1 | tee -a "$RESULTS_FILE"; then
  validation_result=0
  log_test "Workflow Validation" "PASSED"
else
  validation_result=1
  log_test "Workflow Validation" "FAILED"
fi

# Summary
echo "" | tee -a "$RESULTS_FILE"
echo "=== Test Summary ===" | tee -a "$RESULTS_FILE"
echo "Simple Matrix Test: $([ $test_result_1 -eq 0 ] && echo 'PASSED' || echo 'FAILED')" | tee -a "$RESULTS_FILE"
echo "Complex Matrix Test: $([ $test_result_2 -eq 0 ] && echo 'PASSED' || echo 'FAILED')" | tee -a "$RESULTS_FILE"
echo "GitHub Actions Test Job: $([ $act_test_result -eq 0 ] && echo 'PASSED' || echo 'FAILED')" | tee -a "$RESULTS_FILE"
echo "Workflow Validation Job: $([ $validation_result -eq 0 ] && echo 'PASSED' || echo 'FAILED')" | tee -a "$RESULTS_FILE"

# Exit with appropriate code
if [ $test_result_1 -eq 0 ] && [ $test_result_2 -eq 0 ] && [ $act_test_result -eq 0 ] && [ $validation_result -eq 0 ]; then
  echo "" | tee -a "$RESULTS_FILE"
  echo "All tests PASSED" | tee -a "$RESULTS_FILE"
  exit 0
else
  echo "" | tee -a "$RESULTS_FILE"
  echo "Some tests FAILED" | tee -a "$RESULTS_FILE"
  exit 1
fi
