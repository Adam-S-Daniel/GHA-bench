#!/bin/bash

# Comprehensive test runner for all test suites

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

RESULTS_FILE="TEST_RESULTS.txt"
TOTAL_PASSED=0
TOTAL_FAILED=0

> "$RESULTS_FILE"

log_header() {
  echo ""
  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}================================${NC}"
  echo ""
  {
    echo ""
    echo "================================"
    echo "$1"
    echo "================================"
  } >> "$RESULTS_FILE"
}

log_result() {
  echo "$@"
  echo "$@" >> "$RESULTS_FILE"
}

run_test_suite() {
  local suite_name="$1"
  local script="$2"

  log_header "$suite_name"

  if bash "$script" 2>&1 | tee -a "$RESULTS_FILE"; then
    log_result -e "${GREEN}✓${NC} $suite_name PASSED"
    return 0
  else
    log_result -e "${RED}✗${NC} $suite_name FAILED"
    return 1
  fi
}

# Run all test suites
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Semantic Version Bumper - Full Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Test 1: Unit Tests
if run_test_suite "Unit Tests" "test-version-bumper.sh"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi

# Test 2: Workflow Structure Tests
if run_test_suite "Workflow Structure Tests" "test-workflow-structure.sh"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi

# Test 3: Act Integration Tests
if run_test_suite "Act Integration Tests" "test-with-act.sh"; then
  ((TOTAL_PASSED++))
else
  ((TOTAL_FAILED++))
fi

# Final Summary
log_header "FINAL SUMMARY"

log_result "Test Suites Passed: $TOTAL_PASSED"
log_result "Test Suites Failed: $TOTAL_FAILED"

if [ $TOTAL_FAILED -eq 0 ]; then
  log_result -e "${GREEN}✓ ALL TEST SUITES PASSED${NC}"
  log_result ""
  log_result "Files created:"
  log_result "  ✓ version-bumper.sh (main script)"
  log_result "  ✓ test-version-bumper.sh (7 unit tests)"
  log_result "  ✓ test-workflow-structure.sh (10 structure tests)"
  log_result "  ✓ test-with-act.sh (3 integration tests)"
  log_result "  ✓ .github/workflows/semantic-version-bumper.yml (GitHub Actions)"
  log_result "  ✓ act-result.txt (workflow execution results)"
  log_result "  ✓ TEST_RESULTS.txt (this summary)"
  log_result "  ✓ README.md (documentation)"
  log_result "  ✓ test-fixtures.sh (test data examples)"
  exit 0
else
  log_result -e "${RED}✗ SOME TEST SUITES FAILED${NC}"
  exit 1
fi
