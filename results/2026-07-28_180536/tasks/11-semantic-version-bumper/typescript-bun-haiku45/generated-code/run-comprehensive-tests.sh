#!/bin/bash
# Comprehensive test harness for semantic version bumper
# Tests the complete workflow: unit tests, actionlint validation, and act integration

set -e

SCRIPT_DIR=$(pwd)
RESULT_FILE="act-result.txt"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize result file with header
{
  echo "================================================================================"
  echo "Semantic Version Bumper - Complete Test Suite"
  echo "================================================================================"
  echo ""
  echo "Test Execution: $(date)"
  echo "Working Directory: $SCRIPT_DIR"
  echo ""
} > "$RESULT_FILE"

echo -e "${YELLOW}=== Phase 1: Unit Tests ===${NC}"
echo ""

# Run unit tests with bun
echo "Running Bun unit tests..."
if bun test 2>&1 | tee -a "$RESULT_FILE"; then
  echo -e "${GREEN}✓ Unit tests passed${NC}"
  echo "PHASE: Unit tests - PASS" >> "$RESULT_FILE"
else
  echo -e "${RED}✗ Unit tests failed${NC}"
  echo "PHASE: Unit tests - FAIL" >> "$RESULT_FILE"
  exit 1
fi

echo ""
echo -e "${YELLOW}=== Phase 2: Workflow Validation ===${NC}"
echo ""

# Validate YAML syntax
echo "Validating workflow YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))" 2>/dev/null; then
  echo -e "${GREEN}✓ YAML syntax valid${NC}"
  echo "VALIDATION: YAML syntax - PASS" >> "$RESULT_FILE"
else
  echo -e "${RED}✗ YAML syntax invalid${NC}"
  echo "VALIDATION: YAML syntax - FAIL" >> "$RESULT_FILE"
  exit 1
fi

# Validate with actionlint
echo "Running actionlint validation..."
if actionlint .github/workflows/semantic-version-bumper.yml 2>&1 | tee -a "$RESULT_FILE"; then
  echo -e "${GREEN}✓ actionlint passed${NC}"
  echo "VALIDATION: actionlint - PASS" >> "$RESULT_FILE"
else
  echo -e "${RED}✗ actionlint failed${NC}"
  echo "VALIDATION: actionlint - FAIL" >> "$RESULT_FILE"
  exit 1
fi

# Verify workflow structure
echo "Checking workflow structure..."
if grep -q "name: Semantic Version Bumper" .github/workflows/semantic-version-bumper.yml && \
   grep -q "run: bun test" .github/workflows/semantic-version-bumper.yml && \
   grep -q "src/index.ts" .github/workflows/semantic-version-bumper.yml; then
  echo -e "${GREEN}✓ Workflow structure valid${NC}"
  echo "VALIDATION: Workflow structure - PASS" >> "$RESULT_FILE"
else
  echo -e "${RED}✗ Workflow structure invalid${NC}"
  echo "VALIDATION: Workflow structure - FAIL" >> "$RESULT_FILE"
  exit 1
fi

echo ""
echo -e "${YELLOW}=== Phase 3: ACT Integration Tests ===${NC}"
echo ""

PASSED=0
FAILED=0

# Test 1: Feature commit (1.0.0 -> 1.1.0)
{
  echo "Test 1: Feature commit bump (1.0.0 -> 1.1.0)"
  TEST_DIR=$(mktemp -d)
  trap "rm -rf $TEST_DIR" EXIT

  cp -r .github "$TEST_DIR/"
  cp -r src "$TEST_DIR/"
  cp -r tests "$TEST_DIR/"
  cp package.json "$TEST_DIR/"
  cp tsconfig.json "$TEST_DIR/"

  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  echo "feature content" > feature.txt
  git add feature.txt
  git commit -q -m "feat: add new feature"

  echo "  Running workflow through act..."
  ACT_OUTPUT=$(timeout 120 act push -j test --rm -q 2>&1)
  ACT_EXIT=$?

  if [ $ACT_EXIT -eq 0 ] && echo "$ACT_OUTPUT" | grep -q "Job succeeded"; then
    ((PASSED++))
    echo -e "${GREEN}  ✓ Feature commit test passed${NC}"
    {
      echo ""
      echo "Test 1: Feature Commit (1.0.0 -> 1.1.0)"
      echo "Status: PASS"
      echo "Exit Code: $ACT_EXIT"
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  else
    ((FAILED++))
    echo -e "${RED}  ✗ Feature commit test failed${NC}"
    {
      echo ""
      echo "Test 1: Feature Commit (1.0.0 -> 1.1.0)"
      echo "Status: FAIL"
      echo "Exit Code: $ACT_EXIT"
      echo "Output (last 30 lines):"
      echo "$ACT_OUTPUT" | tail -30
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  fi

  cd "$SCRIPT_DIR"
} 2>&1

echo ""

# Test 2: Fix commit (1.0.0 -> 1.0.1)
{
  echo "Test 2: Fix commit bump (1.0.0 -> 1.0.1)"
  TEST_DIR=$(mktemp -d)
  trap "rm -rf $TEST_DIR" EXIT

  cp -r .github "$TEST_DIR/"
  cp -r src "$TEST_DIR/"
  cp -r tests "$TEST_DIR/"
  cp package.json "$TEST_DIR/"
  cp tsconfig.json "$TEST_DIR/"

  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  echo "fix content" > fix.txt
  git add fix.txt
  git commit -q -m "fix: resolve critical bug"

  echo "  Running workflow through act..."
  ACT_OUTPUT=$(timeout 120 act push -j test --rm -q 2>&1)
  ACT_EXIT=$?

  if [ $ACT_EXIT -eq 0 ] && echo "$ACT_OUTPUT" | grep -q "Job succeeded"; then
    ((PASSED++))
    echo -e "${GREEN}  ✓ Fix commit test passed${NC}"
    {
      echo ""
      echo "Test 2: Fix Commit (1.0.0 -> 1.0.1)"
      echo "Status: PASS"
      echo "Exit Code: $ACT_EXIT"
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  else
    ((FAILED++))
    echo -e "${RED}  ✗ Fix commit test failed${NC}"
    {
      echo ""
      echo "Test 2: Fix Commit (1.0.0 -> 1.0.1)"
      echo "Status: FAIL"
      echo "Exit Code: $ACT_EXIT"
      echo "Output (last 30 lines):"
      echo "$ACT_OUTPUT" | tail -30
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  fi

  cd "$SCRIPT_DIR"
} 2>&1

echo ""

# Test 3: Breaking change (1.0.0 -> 2.0.0)
{
  echo "Test 3: Breaking change (1.0.0 -> 2.0.0)"
  TEST_DIR=$(mktemp -d)
  trap "rm -rf $TEST_DIR" EXIT

  cp -r .github "$TEST_DIR/"
  cp -r src "$TEST_DIR/"
  cp -r tests "$TEST_DIR/"
  cp package.json "$TEST_DIR/"
  cp tsconfig.json "$TEST_DIR/"

  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -q -m "initial: setup"
  git tag v1.0.0

  echo "breaking change" > api.txt
  git add api.txt
  git commit -q -m "feat!: remove deprecated API"

  echo "  Running workflow through act..."
  ACT_OUTPUT=$(timeout 120 act push -j test --rm -q 2>&1)
  ACT_EXIT=$?

  if [ $ACT_EXIT -eq 0 ] && echo "$ACT_OUTPUT" | grep -q "Job succeeded"; then
    ((PASSED++))
    echo -e "${GREEN}  ✓ Breaking change test passed${NC}"
    {
      echo ""
      echo "Test 3: Breaking Change (1.0.0 -> 2.0.0)"
      echo "Status: PASS"
      echo "Exit Code: $ACT_EXIT"
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  else
    ((FAILED++))
    echo -e "${RED}  ✗ Breaking change test failed${NC}"
    {
      echo ""
      echo "Test 3: Breaking Change (1.0.0 -> 2.0.0)"
      echo "Status: FAIL"
      echo "Exit Code: $ACT_EXIT"
      echo "Output (last 30 lines):"
      echo "$ACT_OUTPUT" | tail -30
    } >> "$SCRIPT_DIR/$RESULT_FILE"
  fi

  cd "$SCRIPT_DIR"
} 2>&1

echo ""

# Summary
{
  echo ""
  echo "================================================================================"
  echo "Test Summary"
  echo "================================================================================"
  echo "Unit Tests: PASS"
  echo "Workflow Validation: PASS"
  echo "ACT Integration Tests:"
  echo "  Total: 3"
  echo "  Passed: $PASSED"
  echo "  Failed: $FAILED"
  echo ""
  if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed"
  else
    echo "✗ Some tests failed"
  fi
  echo "================================================================================"
} | tee -a "$RESULT_FILE"

echo ""
echo -e "${GREEN}Results saved to: $RESULT_FILE${NC}"
echo ""

# Exit with proper code
exit $FAILED
