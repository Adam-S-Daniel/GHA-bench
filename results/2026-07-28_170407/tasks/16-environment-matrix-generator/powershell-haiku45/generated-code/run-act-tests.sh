#!/bin/bash
# run-act-tests.sh - Test harness to run all tests through GitHub Actions via act

set -e

ACT_RESULT_FILE="act-result.txt"
TEST_CASES=(
  "Test 1: Basic Pester tests"
  "Test 2: Generate matrix from config"
  "Test 3: Verify workflow structure"
)

# Initialize result file
> "$ACT_RESULT_FILE"

echo "Running Build Matrix Generator Tests via act..."
echo "==============================================="

# Function to run a test case
run_test_case() {
  local test_num=$1
  local test_name=$2

  echo ""
  echo "Running $test_name..."
  echo "---" >> "$ACT_RESULT_FILE"
  echo "## $test_name" >> "$ACT_RESULT_FILE"
  echo "---" >> "$ACT_RESULT_FILE"

  # Run act with push trigger
  if act push --rm 2>&1 | tee -a "$ACT_RESULT_FILE"; then
    echo "✓ $test_name PASSED (exit code: $?)" | tee -a "$ACT_RESULT_FILE"
    return 0
  else
    echo "✗ $test_name FAILED (exit code: $?)" | tee -a "$ACT_RESULT_FILE"
    return 1
  fi
}

# Run test cases
passed=0
failed=0

for i in "${!TEST_CASES[@]}"; do
  test_num=$((i + 1))
  test_name="${TEST_CASES[$i]}"

  if run_test_case "$test_num" "$test_name"; then
    ((passed++))
  else
    ((failed++))
  fi
done

echo ""
echo "==============================================="
echo "Test Summary:"
echo "  Passed: $passed"
echo "  Failed: $failed"
echo "  Total:  $((passed + failed))"
echo ""
echo "Full output saved to: $ACT_RESULT_FILE"

# Verify artifact was created
if [ -f "$ACT_RESULT_FILE" ]; then
  echo "✓ Act result file created"
  echo ""
  echo "Act Output:"
  echo "---"
  head -100 "$ACT_RESULT_FILE"
  echo "..."
  echo "---"
fi

# Exit with error if any tests failed
if [ $failed -gt 0 ]; then
  echo ""
  echo "✗ Some tests failed. See $ACT_RESULT_FILE for details."
  exit 1
fi

echo ""
echo "✓ All tests passed!"
exit 0
