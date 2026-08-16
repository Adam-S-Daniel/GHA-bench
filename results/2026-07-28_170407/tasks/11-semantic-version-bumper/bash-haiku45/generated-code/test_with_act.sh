#!/usr/bin/env bash
# Test the workflow with act - simplified version

set -euo pipefail

ACT_RESULT_FILE="act-result.txt"

echo "Running workflow tests with act..."

# Test 1: Run the test job
echo "Test 1: Running test job..." > "$ACT_RESULT_FILE"
echo "======================================" >> "$ACT_RESULT_FILE"

if act push --rm -j test >> "$ACT_RESULT_FILE" 2>&1; then
  echo "✓ Test job succeeded" >> "$ACT_RESULT_FILE"
  STATUS1=0
else
  echo "✗ Test job failed" >> "$ACT_RESULT_FILE"
  STATUS1=1
fi

echo "" >> "$ACT_RESULT_FILE"
echo "Test 2: Checking for expected output patterns..." >> "$ACT_RESULT_FILE"
echo "======================================" >> "$ACT_RESULT_FILE"

# Verify key output exists in act-result.txt
if grep -q "Run all tests" "$ACT_RESULT_FILE"; then
  echo "✓ Found test execution" >> "$ACT_RESULT_FILE"
  STATUS2=0
else
  echo "✗ Did not find test execution" >> "$ACT_RESULT_FILE"
  STATUS2=1
fi

# Final summary
echo "" >> "$ACT_RESULT_FILE"
echo "======================================" >> "$ACT_RESULT_FILE"
if [ $STATUS1 -eq 0 ] && [ $STATUS2 -eq 0 ]; then
  echo "All act tests passed!" | tee -a "$ACT_RESULT_FILE"
  exit 0
else
  echo "Some act tests failed" | tee -a "$ACT_RESULT_FILE"
  exit 1
fi
