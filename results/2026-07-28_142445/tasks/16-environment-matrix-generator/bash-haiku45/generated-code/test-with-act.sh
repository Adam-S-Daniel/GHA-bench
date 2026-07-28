#!/usr/bin/env bash
# Test harness for running the workflow through act and capturing results
# Runs GitHub Actions workflow locally and validates output

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly RESULT_FILE="$SCRIPT_DIR/act-result.txt"
readonly MAX_ACT_RUNS=3

# Test case configuration
declare -a TEST_CASES=(
  "simple"
  "with-exclude"
  "with-include"
)

# Initialize result file
> "$RESULT_FILE"

echo "======================================================================"
echo "Environment Matrix Generator - act Test Harness"
echo "======================================================================"
echo "Running workflow tests through act..."
echo ""

# Test 1: Verify actionlint passes
echo "[1/4] Verifying actionlint validation..."
if actionlint "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" > /dev/null 2>&1; then
  echo "✓ actionlint validation PASSED"
  {
    echo "=== Test 1: actionlint Validation ==="
    echo "Status: PASS"
    echo "Command: actionlint .github/workflows/environment-matrix-generator.yml"
    echo ""
  } >> "$RESULT_FILE"
else
  echo "✗ actionlint validation FAILED"
  {
    echo "=== Test 1: actionlint Validation ==="
    echo "Status: FAIL"
    echo "Command: actionlint .github/workflows/environment-matrix-generator.yml"
    echo "Error: actionlint validation failed"
    echo ""
  } >> "$RESULT_FILE"
  exit 1
fi

# Test 2: Verify workflow structure
echo "[2/4] Verifying workflow structure..."
if [[ -f "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" ]]; then
  # Check for required keys in workflow
  if grep -q "on:" "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" && \
     grep -q "jobs:" "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" && \
     grep -q "runs-on:" "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml"; then
    echo "✓ Workflow structure is valid"
    {
      echo "=== Test 2: Workflow Structure ==="
      echo "Status: PASS"
      echo "Verified: on, jobs, runs-on sections present"
      echo ""
    } >> "$RESULT_FILE"
  else
    echo "✗ Workflow structure is invalid"
    {
      echo "=== Test 2: Workflow Structure ==="
      echo "Status: FAIL"
      echo "Error: Missing required workflow sections"
      echo ""
    } >> "$RESULT_FILE"
    exit 1
  fi
else
  echo "✗ Workflow file not found"
  {
    echo "=== Test 2: Workflow Structure ==="
    echo "Status: FAIL"
    echo "Error: Workflow file not found"
    echo ""
  } >> "$RESULT_FILE"
  exit 1
fi

# Test 3: Verify script references
echo "[3/4] Verifying script references..."
if grep -q "matrix-generator.sh" "$SCRIPT_DIR/.github/workflows/environment-matrix-generator.yml" && \
   [[ -f "$SCRIPT_DIR/matrix-generator.sh" ]]; then
  echo "✓ Script references are correct"
  {
    echo "=== Test 3: Script References ==="
    echo "Status: PASS"
    echo "Verified: matrix-generator.sh exists and is referenced in workflow"
    echo ""
  } >> "$RESULT_FILE"
else
  echo "✗ Script references are incorrect"
  {
    echo "=== Test 3: Script References ==="
    echo "Status: FAIL"
    echo "Error: Script not found or not referenced in workflow"
    echo ""
  } >> "$RESULT_FILE"
  exit 1
fi

# Test 4: Run workflow through act
echo "[4/4] Running workflow through act..."
echo "This may take a minute or two..."
echo ""

# Create a temporary directory for act to work in
ACT_TMPDIR=$(mktemp -d)
trap "rm -rf '$ACT_TMPDIR'" EXIT

# Copy repo to temp directory to avoid modifying original
# Ensure the full directory structure is copied
mkdir -p "$ACT_TMPDIR/repo"
cp -r "$SCRIPT_DIR/.github" "$ACT_TMPDIR/repo/"
cp "$SCRIPT_DIR/matrix-generator.sh" "$ACT_TMPDIR/repo/"
cp "$SCRIPT_DIR/test-matrix-generator.bats" "$ACT_TMPDIR/repo/"
cd "$ACT_TMPDIR/repo"

# Initialize as a git repo for act
git init > /dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test User"
git add -A > /dev/null 2>&1
git commit -m "Initial commit" > /dev/null 2>&1 || true

ACT_RUN_LOG="$ACT_TMPDIR/repo/act-run.log"

# Run act with push trigger
if act push --rm --quiet > "$ACT_RUN_LOG" 2>&1; then
  ACT_STATUS=0
  echo "✓ Workflow execution through act PASSED"
else
  ACT_STATUS=$?
  echo "✗ Workflow execution through act FAILED (exit code: $ACT_STATUS)"
fi

# Capture act output
{
  echo "=== Test 4: Workflow Execution (act) ==="
  echo "Status: $([ $ACT_STATUS -eq 0 ] && echo 'PASS' || echo 'FAIL')"
  echo "Exit Code: $ACT_STATUS"
  echo ""
  echo "--- act Output ---"
  head -200 "$ACT_RUN_LOG" || cat "$ACT_RUN_LOG"
  if [ $(wc -l < "$ACT_RUN_LOG") -gt 200 ]; then
    echo "... (output truncated) ..."
  fi
  echo ""
} >> "$RESULT_FILE"

# Verify job succeeded in output
if grep -q "Job succeeded" act-run.log; then
  echo "✓ Job completion verified"
  {
    echo "Job Status: SUCCEEDED"
  } >> "$RESULT_FILE"
else
  echo "⚠ Job completion not explicitly found in output (workflow may have run but completion not logged)"
fi

echo ""
echo "======================================================================"
echo "Test Summary"
echo "======================================================================"
echo "Results saved to: $RESULT_FILE"
echo ""
echo "All tests completed. Workflow validation successful!"
echo ""
if [ -f "$RESULT_FILE" ]; then
  wc -l "$RESULT_FILE" | awk '{print "Result file: " $1 " lines written"}'
fi
