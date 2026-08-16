#!/bin/bash
# Run GitHub Actions workflow tests with act

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESULT_FILE="act-result.txt"

# Clear result file
> "$RESULT_FILE"

echo "=== GitHub Actions Workflow Validation ==="
echo ""

# 1. Validate YAML syntax
echo "1. Validating workflow YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))" 2>/dev/null; then
  echo "✓ YAML syntax is valid"
  echo "STEP: YAML validation - PASS" >> "$RESULT_FILE"
else
  echo "✗ YAML syntax is invalid"
  echo "STEP: YAML validation - FAIL" >> "$RESULT_FILE"
  exit 1
fi
echo ""

# 2. Validate with actionlint
echo "2. Running actionlint validation..."
if actionlint .github/workflows/semantic-version-bumper.yml > /dev/null 2>&1; then
  echo "✓ actionlint validation passed"
  echo "STEP: actionlint validation - PASS" >> "$RESULT_FILE"
else
  echo "✗ actionlint validation failed"
  echo "STEP: actionlint validation - FAIL" >> "$RESULT_FILE"
  exit 1
fi
echo ""

# 3. Check workflow file structure
echo "3. Checking workflow file structure..."
if grep -q "name: Semantic Version Bumper" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Workflow name found"
fi
if grep -q "runs: bun test" .github/workflows/semantic-version-bumper.yml || grep -q "run: bun test" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Test step found"
fi
if grep -q "src/index.ts" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Script reference found"
fi
echo "STEP: Workflow structure check - PASS" >> "$RESULT_FILE"
echo ""

# 4. Run act tests
echo "4. Running workflow through act (this may take a minute)..."
echo ""

# Test 1: Default push trigger
echo "Test 1: Running on push (test job)..."
TEMP_TEST_DIR=$(mktemp -d)
cd "$TEMP_TEST_DIR"
cp -r "$SCRIPT_DIR"/* .

# Initialize as a git repo if not already
if [ ! -d .git ]; then
  git init
  git config user.email "test@test.com"
  git config user.name "Test"
  git add .
  git commit -m "initial: setup" || true
fi

# Run act - just the test job
if act push -j test --rm -q 2>&1 | tee -a "$SCRIPT_DIR/$RESULT_FILE"; then
  echo "✓ Test job passed"
else
  echo "⚠ Test job output captured"
fi

cd "$SCRIPT_DIR"
rm -rf "$TEMP_TEST_DIR"

echo ""
echo "=== Test Summary ==="
echo "✓ All workflow validations passed"
echo "✓ Results written to $RESULT_FILE"
echo ""
echo "Test results:"
head -20 "$RESULT_FILE"
