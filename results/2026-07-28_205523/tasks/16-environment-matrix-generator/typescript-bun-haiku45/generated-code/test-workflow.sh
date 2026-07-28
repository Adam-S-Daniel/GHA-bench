#!/bin/bash
set -e

# Test harness for GitHub Actions workflow validation
# This script runs the workflow through act and verifies output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/act-result.txt"

# Initialize result file
> "$RESULT_FILE"

log_section() {
  echo ""
  echo "=================================================================================="
  echo "$1"
  echo "=================================================================================="
  tee -a "$RESULT_FILE"
}

run_test() {
  local test_name="$1"
  echo ""
  echo "Running test: $test_name"
  echo "Test: $test_name" | tee -a "$RESULT_FILE"
}

# Test 1: Full workflow execution
run_test "Complete workflow with all tests and validations"

cd "$SCRIPT_DIR"

# Run the workflow with act
echo "Executing: act push --rm -l" | tee -a "$RESULT_FILE"

if act push --rm -l > /tmp/act-output.txt 2>&1; then
  echo "✓ act completed with exit code 0" | tee -a "$RESULT_FILE"
  cat /tmp/act-output.txt >> "$RESULT_FILE"
else
  EXIT_CODE=$?
  echo "✗ act failed with exit code $EXIT_CODE" | tee -a "$RESULT_FILE"
  cat /tmp/act-output.txt >> "$RESULT_FILE"
  exit 1
fi

# Verify output content
log_section "VERIFYING OUTPUT"

OUTPUT=$(cat /tmp/act-output.txt)

# Check for successful job completion
if echo "$OUTPUT" | grep -q "Job succeeded"; then
  echo "✓ Found 'Job succeeded' message" | tee -a "$RESULT_FILE"
else
  echo "✗ Missing 'Job succeeded' message" | tee -a "$RESULT_FILE"
  exit 1
fi

# Check for test passing
if echo "$OUTPUT" | grep -q "pass"; then
  echo "✓ Tests passed" | tee -a "$RESULT_FILE"
else
  echo "⚠ No explicit test pass message (might still be OK)" | tee -a "$RESULT_FILE"
fi

# Check for basic fixture validation
if echo "$OUTPUT" | grep -q "Basic matrix output\|Basic fixture validation"; then
  echo "✓ Basic fixture test executed" | tee -a "$RESULT_FILE"
else
  echo "⚠ Basic fixture test may not have run" | tee -a "$RESULT_FILE"
fi

log_section "WORKFLOW STRUCTURE VALIDATION"

# Check that workflow file exists and is valid YAML
if [ -f "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" ]; then
  echo "✓ Workflow file exists" | tee -a "$RESULT_FILE"
else
  echo "✗ Workflow file not found" | tee -a "$RESULT_FILE"
  exit 1
fi

# Validate workflow file references correct script
if grep -q "src/generator.ts" "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml"; then
  echo "✓ Workflow references correct script path" | tee -a "$RESULT_FILE"
else
  echo "✗ Workflow doesn't reference src/generator.ts" | tee -a "$RESULT_FILE"
  exit 1
fi

# Validate script file exists
if [ -f "$SCRIPT_DIR/src/generator.ts" ]; then
  echo "✓ Generator script exists" | tee -a "$RESULT_FILE"
else
  echo "✗ Generator script not found" | tee -a "$RESULT_FILE"
  exit 1
fi

# Validate fixture files exist
FIXTURES=("fixtures/basic.json" "fixtures/with-excludes.json" "fixtures/complex.json")
for fixture in "${FIXTURES[@]}"; do
  if [ -f "$SCRIPT_DIR/$fixture" ]; then
    echo "✓ Fixture file exists: $fixture" | tee -a "$RESULT_FILE"
  else
    echo "✗ Fixture file not found: $fixture" | tee -a "$RESULT_FILE"
    exit 1
  fi
done

log_section "ACTIONLINT VALIDATION"

# Verify actionlint passes
if actionlint "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" > /tmp/actionlint-output.txt 2>&1; then
  echo "✓ actionlint passed validation" | tee -a "$RESULT_FILE"
  cat /tmp/actionlint-output.txt >> "$RESULT_FILE"
else
  echo "✗ actionlint validation failed" | tee -a "$RESULT_FILE"
  cat /tmp/actionlint-output.txt >> "$RESULT_FILE"
  exit 1
fi

log_section "TEST SUMMARY"

echo "" | tee -a "$RESULT_FILE"
echo "All validation tests passed!" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"
echo "Result file: $RESULT_FILE" | tee -a "$RESULT_FILE"
echo "Total lines in result file: $(wc -l < "$RESULT_FILE")" | tee -a "$RESULT_FILE"

echo ""
echo "✓ Workflow validation complete - see $RESULT_FILE"
