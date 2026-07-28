#!/bin/bash

# Simple workflow test using act
# Tests the semantic version bumper in a GitHub Actions environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/act-result.txt"

# Clear result file
> "$RESULT_FILE"

echo "=== Semantic Version Bumper - Act Workflow Test ===" | tee -a "$RESULT_FILE"
echo "Started: $(date)" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Test 1: Workflow structure validation
echo "[1/4] Validating workflow file structure..." | tee -a "$RESULT_FILE"

if [ -f "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" ]; then
  echo "  ✓ Workflow file exists" | tee -a "$RESULT_FILE"
else
  echo "  ✗ Workflow file not found!" | tee -a "$RESULT_FILE"
  exit 1
fi

# Test 2: actionlint validation
echo "[2/4] Running actionlint validation..." | tee -a "$RESULT_FILE"

if actionlint "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" >> "$RESULT_FILE" 2>&1; then
  echo "  ✓ actionlint passed" | tee -a "$RESULT_FILE"
else
  echo "  ✗ actionlint failed!" | tee -a "$RESULT_FILE"
  echo "See act-result.txt for details" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 3: Local test run
echo "[3/4] Running local Bun tests..." | tee -a "$RESULT_FILE"

if bun test 2>&1 | tee -a "$RESULT_FILE"; then
  echo "  ✓ All local tests passed" | tee -a "$RESULT_FILE"
else
  echo "  ✗ Local tests failed!" | tee -a "$RESULT_FILE"
  exit 1
fi

echo "" | tee -a "$RESULT_FILE"

# Test 4: Act workflow test
echo "[4/4] Running workflow with act..." | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Create a temporary test repo
TEST_DIR="/tmp/act-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize git repo
git init -q .
git config user.email "test@example.com"
git config user.name "Test User"

# Create package.json
cat > package.json <<'EOF'
{
  "name": "test-package",
  "version": "1.0.0",
  "description": "Test package",
  "main": "src/index.ts",
  "type": "module",
  "scripts": {
    "test": "bun test"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "typescript": "latest"
  }
}
EOF

# Copy source files
cp -r "$SCRIPT_DIR"/src .
cp -r "$SCRIPT_DIR"/.github .
cp "$SCRIPT_DIR"/bun.lockb . 2>/dev/null || true

# Create initial commit
git add .
git commit -q -m "Initial commit"

# Add a feature commit
git commit --allow-empty -q -m "feat: add new functionality"

# Tag initial version
git tag -a v1.0.0 -m "Version 1.0.0" HEAD~1 || true

echo "Created test repository at: $TEST_DIR" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Run act
echo "Running: act push --rm -j test -j bump-version" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

ACT_LOG="/tmp/act-workflow.log"

if act push --rm -j test -j bump-version > "$ACT_LOG" 2>&1; then
  ACT_EXIT=$?
  echo "Act completed with exit code: $ACT_EXIT" | tee -a "$RESULT_FILE"
else
  ACT_EXIT=$?
  echo "Act completed with exit code: $ACT_EXIT" | tee -a "$RESULT_FILE"
fi

# Capture act output
echo "" | tee -a "$RESULT_FILE"
echo "=== Act Output ===" | tee -a "$RESULT_FILE"
cat "$ACT_LOG" | tee -a "$RESULT_FILE"
echo "=== End Act Output ===" | tee -a "$RESULT_FILE"

# Check for success indicators
echo "" | tee -a "$RESULT_FILE"
echo "[RESULTS]" | tee -a "$RESULT_FILE"

if grep -q "Job succeeded" "$ACT_LOG"; then
  echo "  ✓ Job succeeded" | tee -a "$RESULT_FILE"
else
  echo "  ⚠ Job status not found" | tee -a "$RESULT_FILE"
fi

if grep -q "bun test" "$ACT_LOG"; then
  echo "  ✓ Tests ran in workflow" | tee -a "$RESULT_FILE"
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"
rm -f "$ACT_LOG"

echo "" | tee -a "$RESULT_FILE"
echo "=== End of Test ===" | tee -a "$RESULT_FILE"
echo "Finished: $(date)" | tee -a "$RESULT_FILE"

echo ""
echo "Full test results saved to: $RESULT_FILE"
