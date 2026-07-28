#!/bin/bash

# Test script for semantic version bumper
# Run all tests and generate act-result.txt

set -e

RESULT_FILE="act-result.txt"
EXIT_CODE=0

echo "=== Semantic Version Bumper - Comprehensive Test Suite ===" > "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "Test Environment:" >> "$RESULT_FILE"
echo "- OS: $(uname -s)" >> "$RESULT_FILE"
echo "- Bun: $(bun --version)" >> "$RESULT_FILE"
echo "- Date: $(date)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

echo "Running unit tests..." | tee -a "$RESULT_FILE"
if bun test; then
  echo "✓ Unit tests PASSED" | tee -a "$RESULT_FILE"
else
  echo "✗ Unit tests FAILED" | tee -a "$RESULT_FILE"
  EXIT_CODE=1
fi

echo "" >> "$RESULT_FILE"
echo "Running integration tests..." | tee -a "$RESULT_FILE"

# Test 1: Patch bump
echo "" | tee -a "$RESULT_FILE"
echo "Test 1: Patch bump scenario" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-patch-bump-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "fix: correct typo" "fix: handle null pointer" > output.txt 2>&1; then
  if grep -q "1.0.1" package.json; then
    echo "  ✓ Patch bump PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    grep "1.0.1" package.json | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Patch bump FAILED: version not updated to 1.0.1" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Patch bump FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Test 2: Minor bump
echo "" | tee -a "$RESULT_FILE"
echo "Test 2: Minor bump scenario" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-minor-bump-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "feat: new feature" "fix: bug fix" > output.txt 2>&1; then
  if grep -q "1.1.0" package.json; then
    echo "  ✓ Minor bump PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    grep "1.1.0" package.json | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Minor bump FAILED: version not updated to 1.1.0" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Minor bump FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Test 3: Major bump
echo "" | tee -a "$RESULT_FILE"
echo "Test 3: Major bump scenario" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-major-bump-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "feat!: breaking change to API" > output.txt 2>&1; then
  if grep -q "2.0.0" package.json; then
    echo "  ✓ Major bump PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    grep "2.0.0" package.json | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Major bump FAILED: version not updated to 2.0.0" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Major bump FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Test 4: Dry run
echo "" | tee -a "$RESULT_FILE"
echo "Test 4: Dry-run mode" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-dry-run-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "feat: test" --dry-run > output.txt 2>&1; then
  if grep -q "1.1.0" output.txt && ! grep -q "1.1.0" package.json; then
    echo "  ✓ Dry-run PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    echo "  (version shown but not written)" | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Dry-run FAILED: version was written or not shown" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Dry-run FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Test 5: Breaking change with exclamation mark
echo "" | tee -a "$RESULT_FILE"
echo "Test 5: Breaking change with ! detection" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-breaking-footer-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "refactor!: database layer completely rewritten" > output.txt 2>&1; then
  if grep -q "2.0.0" package.json; then
    echo "  ✓ Breaking change detection PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    grep "2.0.0" package.json | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Breaking change detection FAILED: version not updated to 2.0.0" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Breaking change detection FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Test 6: Changelog generation
echo "" | tee -a "$RESULT_FILE"
echo "Test 6: Changelog generation" | tee -a "$RESULT_FILE"
TEST_DIR="/tmp/test-changelog-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0"
}
EOF

if bun run "$OLDPWD/main.ts" package.json "feat: new auth system" "fix: memory leak" > output.txt 2>&1; then
  if grep -q "Features" output.txt && grep -q "Bug Fixes" output.txt; then
    echo "  ✓ Changelog generation PASSED" | tee -a "$OLDPWD/$RESULT_FILE"
    grep -A 10 "Changelog:" output.txt | head -5 | tee -a "$OLDPWD/$RESULT_FILE"
  else
    echo "  ✗ Changelog generation FAILED" | tee -a "$OLDPWD/$RESULT_FILE"
    EXIT_CODE=1
  fi
else
  echo "  ✗ Changelog generation FAILED: script error" | tee -a "$OLDPWD/$RESULT_FILE"
  cat output.txt | tee -a "$OLDPWD/$RESULT_FILE"
  EXIT_CODE=1
fi

cd - > /dev/null

# Summary
echo "" | tee -a "$RESULT_FILE"
echo "=== Test Summary ===" | tee -a "$RESULT_FILE"
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ All tests PASSED" | tee -a "$RESULT_FILE"
  echo "Status: SUCCESS" | tee -a "$RESULT_FILE"
else
  echo "✗ Some tests FAILED" | tee -a "$RESULT_FILE"
  echo "Status: FAILURE" | tee -a "$RESULT_FILE"
fi

echo "" | tee -a "$RESULT_FILE"
echo "Test results saved to: $RESULT_FILE" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

exit $EXIT_CODE
