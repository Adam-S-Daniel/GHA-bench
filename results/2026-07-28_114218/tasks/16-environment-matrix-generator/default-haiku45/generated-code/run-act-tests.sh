#!/bin/bash
# Test runner for GitHub Actions workflow using 'act'
# Runs all tests through the CI/CD pipeline and captures output

set -e

RESULTS_FILE="act-result.txt"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Clear results file
> "$RESULTS_FILE"

log_test() {
  local test_name=$1
  local status=$2
  local output=$3

  TEST_COUNT=$((TEST_COUNT + 1))

  echo "=================================================================================" >> "$RESULTS_FILE"
  echo "Test Case #$TEST_COUNT: $test_name" >> "$RESULTS_FILE"
  echo "Status: $status" >> "$RESULTS_FILE"
  echo "=================================================================================" >> "$RESULTS_FILE"
  echo "$output" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"

  if [ "$status" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "✓ $test_name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "✗ $test_name"
  fi
}

echo "Running GitHub Actions workflow tests with 'act'..."
echo "Results will be saved to $RESULTS_FILE"
echo ""

# Test 1: Basic workflow execution
echo "Test 1: Running workflow (test job)..."
OUTPUT=$(act push --rm --job test 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "All tests.*pass"; then
  log_test "Basic workflow execution (test job)" "PASS" "$OUTPUT"
else
  log_test "Basic workflow execution (test job)" "FAIL" "$OUTPUT"
fi

# Test 2: Matrix validation job
echo "Test 2: Running workflow (matrix-validation job)..."
OUTPUT=$(act push --rm --job matrix-validation 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "passed"; then
  log_test "Matrix validation job" "PASS" "$OUTPUT"
else
  log_test "Matrix validation job" "FAIL" "$OUTPUT"
fi

# Test 3: Example matrix generation job
echo "Test 3: Running workflow (generate-example-matrix job)..."
OUTPUT=$(act push --rm --job generate-example-matrix 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "include"; then
  log_test "Example matrix generation" "PASS" "$OUTPUT"
else
  log_test "Example matrix generation" "FAIL" "$OUTPUT"
fi

# Summary
echo ""
echo "Test Summary:"
echo "  Total: $TEST_COUNT"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo ""
echo "Results saved to: $RESULTS_FILE"

if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
fi

exit 0
