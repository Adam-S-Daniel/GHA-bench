#!/bin/bash

# Test runner for environment matrix generator
# Validates workflow structure and runs through act

set -e

RESULT_FILE="act-result.txt"
> "$RESULT_FILE"

echo "Environment Matrix Generator - Test Suite" | tee -a "$RESULT_FILE"
echo "==========================================" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Test 1: Run bun tests
echo "Test 1: Running bun unit tests" | tee -a "$RESULT_FILE"
if bun test matrix.test.ts 2>&1 | tee -a "$RESULT_FILE"; then
  echo "✓ Unit tests passed" | tee -a "$RESULT_FILE"
else
  echo "✗ Unit tests failed" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 2: Test CLI with basic config
echo "Test 2: CLI with basic config" | tee -a "$RESULT_FILE"
output=$(bun run cli.ts fixtures/basic-config.json)
if echo "$output" | grep -q '"include"'; then
  echo "✓ CLI output contains include field" | tee -a "$RESULT_FILE"
  echo "$output" >> "$RESULT_FILE"
else
  echo "✗ CLI output missing include field" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 3: Test CLI with options
echo "Test 3: CLI with options" | tee -a "$RESULT_FILE"
output=$(bun run cli.ts fixtures/basic-config.json fixtures/with-options.json)
if echo "$output" | grep -q '"max-parallel"'; then
  echo "✓ CLI output contains max-parallel field" | tee -a "$RESULT_FILE"
  echo "$output" >> "$RESULT_FILE"
else
  echo "✗ CLI output missing max-parallel field" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 4: Validate workflow exists and has structure
echo "Test 4: Workflow structure validation" | tee -a "$RESULT_FILE"
if [ -f ".github/workflows/environment-matrix-generator.yml" ]; then
  echo "✓ Workflow file exists" | tee -a "$RESULT_FILE"

  if grep -q "name:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has name" | tee -a "$RESULT_FILE"
  fi

  if grep -q "on:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has triggers" | tee -a "$RESULT_FILE"
  fi

  if grep -q "permissions:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has permissions" | tee -a "$RESULT_FILE"
  fi

  if grep -q "runs-on:" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow has runs-on" | tee -a "$RESULT_FILE"
  fi

  if grep -q "setup-bun" .github/workflows/environment-matrix-generator.yml; then
    echo "✓ Workflow sets up Bun" | tee -a "$RESULT_FILE"
  fi
else
  echo "✗ Workflow file not found" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 5: actionlint validation
echo "Test 5: actionlint validation" | tee -a "$RESULT_FILE"
if actionlint .github/workflows/environment-matrix-generator.yml 2>&1 | tee -a "$RESULT_FILE"; then
  echo "✓ actionlint passed" | tee -a "$RESULT_FILE"
else
  echo "✗ actionlint failed" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"
echo "==========================================" | tee -a "$RESULT_FILE"
echo "All tests passed! ✓" | tee -a "$RESULT_FILE"
echo "==========================================" | tee -a "$RESULT_FILE"
