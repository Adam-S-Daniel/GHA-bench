#!/bin/bash

# Test workflow structure and validation

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
  local expected="$1" actual="$2" test_name="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "${GREEN}✓${NC} $test_name"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $test_name"
    echo "  Expected: $expected"
    echo "  Actual: $actual"
    ((TESTS_FAILED++))
  fi
}

assert_file_exists() {
  local file="$1" test_name="$2"
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $test_name"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $test_name - File not found: $file"
    ((TESTS_FAILED++))
  fi
}

assert_executable() {
  local file="$1" test_name="$2"
  if [ -x "$file" ]; then
    echo -e "${GREEN}✓${NC} $test_name"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $test_name - File not executable: $file"
    ((TESTS_FAILED++))
  fi
}

echo "Testing Workflow Structure"
echo "=========================="

# Test 1: Workflow file exists
assert_file_exists ".github/workflows/semantic-version-bumper.yml" "Workflow file exists"

# Test 2: Script file exists
assert_file_exists "version-bumper.sh" "Script file exists"

# Test 3: Script is executable
assert_executable "version-bumper.sh" "Script is executable"

# Test 4: actionlint validation
echo -n "Running actionlint... "
if actionlint .github/workflows/semantic-version-bumper.yml > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} actionlint validation passes"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} actionlint validation fails"
  ((TESTS_FAILED++))
fi

# Test 5: Workflow has correct triggers
if grep -q "on:" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓${NC} Workflow has trigger events configured"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Workflow missing trigger events"
  ((TESTS_FAILED++))
fi

# Test 6: Workflow references version-bumper.sh
if grep -q "version-bumper.sh" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓${NC} Workflow references version-bumper.sh"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Workflow does not reference version-bumper.sh"
  ((TESTS_FAILED++))
fi

# Test 7: Workflow has jobs defined
if grep -q "jobs:" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓${NC} Workflow has jobs section"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Workflow missing jobs section"
  ((TESTS_FAILED++))
fi

# Test 8: Workflow has version-bump job
if grep -q "version-bump:" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓${NC} Workflow has version-bump job"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Workflow missing version-bump job"
  ((TESTS_FAILED++))
fi

# Test 9: Workflow uses checkout action
if grep -q "actions/checkout" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓${NC} Workflow uses checkout action"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Workflow missing checkout action"
  ((TESTS_FAILED++))
fi

# Test 10: All unit tests pass
echo -n "Running unit tests... "
if bash test-version-bumper.sh > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} All unit tests pass"
  ((TESTS_PASSED++))
else
  echo -e "${RED}✗${NC} Unit tests failed"
  ((TESTS_FAILED++))
fi

echo "=========================="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

[ $TESTS_FAILED -eq 0 ]
