#!/usr/bin/env bash

# Test runner script to validate matrix generator through GitHub Actions workflow via act

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/act-result.txt"
ACT_RUNS=0
ACT_MAX_RUNS=3

# Clear result file
> "$RESULT_FILE"

# Test case structure
declare -a TEST_CASES=(
  "test"
  "actionlint"
)

echo "=== Running Act Tests ==="
echo "Result file: $RESULT_FILE"
echo

# Run workflow tests via act
run_act_test() {
  local job="$1"
  local run_num=$((ACT_RUNS + 1))

  if [[ $run_num -gt $ACT_MAX_RUNS ]]; then
    echo "WARNING: Maximum act runs exceeded ($ACT_MAX_RUNS). Skipping job: $job" | tee -a "$RESULT_FILE"
    return 1
  fi

  echo "Running act push (run $run_num/$ACT_MAX_RUNS) for job: $job" | tee -a "$RESULT_FILE"
  echo "================================================" | tee -a "$RESULT_FILE"

  if act push --rm -j "$job" 2>&1 | tee -a "$RESULT_FILE"; then
    echo "✓ Job '$job' succeeded" | tee -a "$RESULT_FILE"
    echo "================================================" | tee -a "$RESULT_FILE"
    echo | tee -a "$RESULT_FILE"
    ACT_RUNS=$run_num
    return 0
  else
    local exit_code=$?
    echo "✗ Job '$job' failed with exit code $exit_code" | tee -a "$RESULT_FILE"
    echo "================================================" | tee -a "$RESULT_FILE"
    echo | tee -a "$RESULT_FILE"
    return $exit_code
  fi
}

# Run tests for each job
for job in "${TEST_CASES[@]}"; do
  if ! run_act_test "$job"; then
    echo "ERROR: Failed to run test job: $job"
    exit 1
  fi
done

echo "=== Act Test Summary ===" | tee -a "$RESULT_FILE"
echo "Total act runs: $ACT_RUNS/$ACT_MAX_RUNS" | tee -a "$RESULT_FILE"
echo "Result file: $RESULT_FILE" | tee -a "$RESULT_FILE"

# Verify result file exists and has content
if [[ ! -s "$RESULT_FILE" ]]; then
  echo "ERROR: Result file is empty or does not exist: $RESULT_FILE"
  exit 1
fi

echo | tee -a "$RESULT_FILE"
echo "✓ All act tests completed successfully" | tee -a "$RESULT_FILE"
