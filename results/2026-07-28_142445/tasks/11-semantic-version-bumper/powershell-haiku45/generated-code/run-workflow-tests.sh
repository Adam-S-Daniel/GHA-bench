#!/bin/bash
# Test harness for semantic version bumper GitHub Actions workflow
# Runs act with multiple test cases and captures output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/act-result.txt"

# Test cases (limit to 3 as per requirements)
declare -a TEST_CASES=(
  "patch-bump:fix: correct bug|fix: handle edge case"
  "minor-bump:feat: new feature|fix: small fix"
  "major-bump:feat: redesign API!|BREAKING CHANGE: removed endpoints"
)

echo "=== Semantic Version Bumper - Workflow Test Suite ===" | tee "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

PASSED=0
FAILED=0
TEST_NUM=1

for TEST_CASE in "${TEST_CASES[@]}"; do
  IFS=':' read -r TEST_NAME COMMITS <<< "$TEST_CASE"

  echo "────────────────────────────────────────────────────" | tee -a "$RESULT_FILE"
  echo "Test Case $TEST_NUM: $TEST_NAME" | tee -a "$RESULT_FILE"
  echo "────────────────────────────────────────────────────" | tee -a "$RESULT_FILE"

  # Create temporary test directory
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT

  # Initialize git repo
  cd "$TEMP_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create package.json
  echo '{"name":"test-package","version":"1.0.0"}' > package.json
  git add package.json
  git commit -q -m "chore: initial commit"

  # Add test commits
  IFS='|' read -ra COMMIT_ARRAY <<< "$COMMITS"
  for COMMIT_MSG in "${COMMIT_ARRAY[@]}"; do
    touch "file-$RANDOM.txt"
    git add .
    git commit -q -m "$COMMIT_MSG"
  done

  # Copy scripts
  cp "$SCRIPT_DIR"/{version-bumper.ps1,bump-version.ps1,test-version-bumper.ps1} .
  cp -r "$SCRIPT_DIR/.github" .

  # Run act and capture output
  echo "Running workflow..." | tee -a "$RESULT_FILE"
  ACT_OUTPUT=$(timeout 120 act push --rm 2>&1 || true)
  ACT_EXIT_CODE=$?

  echo "$ACT_OUTPUT" >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"

  # Check results
  if echo "$ACT_OUTPUT" | grep -q "Job succeeded"; then
    echo "✓ Test $TEST_NUM passed (Exit code: $ACT_EXIT_CODE)" | tee -a "$RESULT_FILE"
    ((PASSED++))
  else
    echo "✗ Test $TEST_NUM failed (Exit code: $ACT_EXIT_CODE)" | tee -a "$RESULT_FILE"
    ((FAILED++))
  fi

  echo "" | tee -a "$RESULT_FILE"
  ((TEST_NUM++))
done

# Summary
echo "=== Test Summary ===" | tee -a "$RESULT_FILE"
echo "Passed: $PASSED/$((PASSED + FAILED))" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

if [ $FAILED -gt 0 ]; then
  echo "Some tests failed!" | tee -a "$RESULT_FILE"
  exit 1
else
  echo "All tests passed!" | tee -a "$RESULT_FILE"
  exit 0
fi
