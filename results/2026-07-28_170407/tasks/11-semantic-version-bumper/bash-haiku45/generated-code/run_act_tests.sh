#!/usr/bin/env bash
# Test harness for running workflow tests with act

set -euo pipefail

ACT_RESULT_FILE="act-result.txt"
WORKSPACE_DIR="$(pwd)"

# Clean up any previous results
> "$ACT_RESULT_FILE"

echo "Starting act workflow tests..." | tee -a "$ACT_RESULT_FILE"

# Test 1: Verify test job runs successfully
echo "========== Test Case 1: Run all tests ==========" | tee -a "$ACT_RESULT_FILE"
if act push --rm -j test 2>&1 | tee -a "$ACT_RESULT_FILE"; then
  echo "✓ Test case 1 PASSED" | tee -a "$ACT_RESULT_FILE"
else
  echo "✗ Test case 1 FAILED" | tee -a "$ACT_RESULT_FILE"
  exit 1
fi

# Test 2: Verify workflow structure with workflow_dispatch
echo "" | tee -a "$ACT_RESULT_FILE"
echo "========== Test Case 2: Workflow dispatch validation ==========" | tee -a "$ACT_RESULT_FILE"
if act workflow_dispatch --rm -j test 2>&1 | tee -a "$ACT_RESULT_FILE"; then
  echo "✓ Test case 2 PASSED" | tee -a "$ACT_RESULT_FILE"
else
  echo "✗ Test case 2 FAILED" | tee -a "$ACT_RESULT_FILE"
  exit 1
fi

# Test 3: Verify push event handling
echo "" | tee -a "$ACT_RESULT_FILE"
echo "========== Test Case 3: Push event handling ==========" | tee -a "$ACT_RESULT_FILE"
if act push --rm -e .github/workflows/.push_event.json -j test 2>&1 | tee -a "$ACT_RESULT_FILE"; then
  echo "✓ Test case 3 PASSED" | tee -a "$ACT_RESULT_FILE"
else
  echo "✗ Test case 3 FAILED" | tee -a "$ACT_RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$ACT_RESULT_FILE"
echo "========== All act tests completed successfully ==========" | tee -a "$ACT_RESULT_FILE"
echo "Results written to: $ACT_RESULT_FILE"
