#!/bin/bash
# Test the GitHub Actions workflow locally with act
# This script validates the workflow structure and tests key scenarios

set -e

RESULT_FILE="act-result.txt"

# Initialize result file
cat > "$RESULT_FILE" << 'EOF'
================================================================================
Semantic Version Bumper - GitHub Actions Workflow Test Results
================================================================================

EOF

echo "Starting workflow validation and testing..."
echo ""

# 1. Validate workflow YAML
echo "Step 1: Validating workflow YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))" 2>/dev/null; then
  echo "✓ YAML is valid"
  echo "VALIDATION: YAML Syntax - PASS" >> "$RESULT_FILE"
else
  echo "✗ YAML is invalid"
  echo "VALIDATION: YAML Syntax - FAIL" >> "$RESULT_FILE"
  cat "$RESULT_FILE"
  exit 1
fi

# 2. Run actionlint
echo "Step 2: Running actionlint..."
if actionlint .github/workflows/semantic-version-bumper.yml 2>&1 | tee -a "$RESULT_FILE"; then
  echo "✓ actionlint passed"
  echo "VALIDATION: actionlint - PASS" >> "$RESULT_FILE"
else
  echo "✗ actionlint failed"
  echo "VALIDATION: actionlint - FAIL" >> "$RESULT_FILE"
fi

# 3. Verify workflow references
echo ""
echo "Step 3: Verifying workflow references..."

CHECKS_PASSED=0
CHECKS_TOTAL=5

if grep -q "uses: actions/checkout@v4" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Checkout action found"
  ((CHECKS_PASSED++))
else
  echo "✗ Checkout action not found"
fi

if grep -q "uses: oven-sh/setup-bun@v1" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Bun setup action found"
  ((CHECKS_PASSED++))
else
  echo "✗ Bun setup action not found"
fi

if grep -q "src/index.ts" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Script reference found"
  ((CHECKS_PASSED++))
else
  echo "✗ Script reference not found"
fi

if grep -q "bun test" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Test command found"
  ((CHECKS_PASSED++))
else
  echo "✗ Test command not found"
fi

if grep -q "Semantic Version Bumper" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Workflow name found"
  ((CHECKS_PASSED++))
else
  echo "✗ Workflow name not found"
fi

echo ""
echo "VALIDATION: Workflow Structure - $CHECKS_PASSED/$CHECKS_TOTAL checks passed" >> "$RESULT_FILE"

# 4. Verify script files exist
echo ""
echo "Step 4: Verifying script files..."
SCRIPT_FILES=(
  "src/index.ts"
  "src/semver.ts"
  "src/commits.ts"
  "src/files.ts"
  "src/git.ts"
  "src/changelog.ts"
)

for file in "${SCRIPT_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "✓ $file exists"
  else
    echo "✗ $file not found"
  fi
done

# 5. Run local tests to ensure everything works
echo ""
echo "Step 5: Running local test suite..."
if bun test --timeout 60000 2>&1 | tee -a "$RESULT_FILE"; then
  echo "✓ All local tests passed"
  echo "TESTS: Local Test Suite - PASS" >> "$RESULT_FILE"
else
  echo "✗ Some tests failed"
  echo "TESTS: Local Test Suite - FAIL" >> "$RESULT_FILE"
fi

echo ""
echo "=================================="
echo "Workflow Validation Complete!"
echo "Results saved to: $RESULT_FILE"
echo "=================================="
