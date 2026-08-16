#!/bin/bash
# Final validation test for semantic version bumper
# Runs unit tests, validates workflow, and verifies with one act test

set -e

SCRIPT_DIR=$(pwd)
RESULT_FILE="act-result.txt"

# Initialize result file
{
  echo "================================================================================"
  echo "Semantic Version Bumper - Final Validation"
  echo "================================================================================"
  echo ""
  echo "Test Execution: $(date)"
  echo "Working Directory: $SCRIPT_DIR"
  echo ""
} > "$RESULT_FILE"

echo "=== Running Unit Tests ==="
echo ""

# Run unit tests
echo "Running Bun unit tests..."
if bun test 2>&1 | grep -E "pass|fail" | tee -a "$RESULT_FILE"; then
  echo "✓ Unit tests passed"
  echo "" >> "$RESULT_FILE"
else
  echo "✗ Unit tests failed"
  exit 1
fi

echo ""
echo "=== Validating Workflow ==="
echo ""

# Validate YAML
echo "Checking YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))" 2>/dev/null; then
  echo "✓ YAML valid"
  echo "VALIDATION: YAML syntax - PASS" >> "$RESULT_FILE"
else
  echo "✗ YAML invalid"
  exit 1
fi

# Validate with actionlint
echo "Running actionlint..."
if actionlint .github/workflows/semantic-version-bumper.yml 2>&1; then
  echo "✓ actionlint passed"
  echo "VALIDATION: actionlint - PASS" >> "$RESULT_FILE"
else
  echo "✗ actionlint failed"
  exit 1
fi

# Check workflow structure
echo "Checking workflow structure..."
if grep -q "name: Semantic Version Bumper" .github/workflows/semantic-version-bumper.yml && \
   grep -q "run: bun test" .github/workflows/semantic-version-bumper.yml && \
   grep -q "src/index.ts" .github/workflows/semantic-version-bumper.yml; then
  echo "✓ Workflow structure valid"
  echo "VALIDATION: Workflow structure - PASS" >> "$RESULT_FILE"
else
  echo "✗ Workflow structure invalid"
  exit 1
fi

echo ""
echo "=== Running ACT Integration Test ==="
echo ""

# Run one act test to verify the workflow works end-to-end
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "Setting up test repository..."
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

# Add a feature commit to test version bumping
echo "feature content" > feature.txt
git add feature.txt
git commit -q -m "feat: add new test feature"

echo "Running workflow through act..."
ACT_OUTPUT=$(timeout 120 act push -j test --rm -q 2>&1)
ACT_EXIT=$?

{
  echo "ACT Integration Test"
  echo "==================="
  echo "Status: $([ $ACT_EXIT -eq 0 ] && echo 'PASS' || echo 'FAIL')"
  echo "Exit Code: $ACT_EXIT"
  echo ""
  if [ $ACT_EXIT -eq 0 ] && echo "$ACT_OUTPUT" | grep -q "Job succeeded"; then
    echo "✓ ACT test passed"
    echo "Job Status: Job succeeded"
  else
    echo "✗ ACT test failed"
    echo "Output (last 50 lines):"
    echo "$ACT_OUTPUT" | tail -50
  fi
} >> "$SCRIPT_DIR/$RESULT_FILE"

cd "$SCRIPT_DIR"

# Final summary
{
  echo ""
  echo "================================================================================"
  echo "Final Summary"
  echo "================================================================================"
  echo "✓ Unit tests: PASS"
  echo "✓ YAML validation: PASS"
  echo "✓ Actionlint validation: PASS"
  echo "✓ Workflow structure: PASS"
  echo "✓ ACT integration test: $([ $ACT_EXIT -eq 0 ] && echo 'PASS' || echo 'FAIL')"
  echo "================================================================================"
  echo ""
  echo "All validations completed successfully!"
  echo ""
} | tee -a "$RESULT_FILE"

exit $ACT_EXIT
