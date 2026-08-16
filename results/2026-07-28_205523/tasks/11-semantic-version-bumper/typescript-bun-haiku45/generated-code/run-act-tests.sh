#!/bin/bash

# Test harness for running semantic version bumper through GitHub Actions with act
# This script runs multiple test cases and verifies the output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$SCRIPT_DIR/act-result.txt"
ACT_LOGS="/tmp/act-logs"

# Clean up result file
> "$RESULT_FILE"

# Test cases - array of tuples: (description, version_input, expected_output)
declare -a TEST_CASES=(
  "patch|1.0.0"
  "minor|1.0.0"
  "major|1.0.0"
)

echo "Starting semantic version bumper tests..." >> "$RESULT_FILE"
echo "Timestamp: $(date)" >> "$RESULT_FILE"
echo "======================================" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

run_test_case() {
  local test_name="$1"
  local initial_version="$2"
  local expected_version="$3"
  local commit_type="$4"

  echo "[TEST] Running: $test_name" | tee -a "$RESULT_FILE"
  echo "  Initial version: $initial_version" | tee -a "$RESULT_FILE"
  echo "  Expected version: $expected_version" | tee -a "$RESULT_FILE"

  # Create temporary test directory
  local test_dir="/tmp/version-bump-test-$$"
  mkdir -p "$test_dir"

  cd "$test_dir"

  # Initialize git repo with initial version
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial package.json with starting version
  cat > package.json <<EOF
{
  "name": "test-package",
  "version": "$initial_version",
  "description": "Test package"
}
EOF

  # Create initial commit
  git add package.json
  git commit -q -m "Initial commit"

  # Add test commit based on type
  case "$commit_type" in
    patch)
      git commit --allow-empty -q -m "fix: resolve bug in module"
      ;;
    minor)
      git commit --allow-empty -q -m "feat: add new feature"
      ;;
    major)
      git commit --allow-empty -q -m "feat!: redesign API"
      ;;
  esac

  # Create tag for initial version
  git tag -a "v$initial_version" -m "Version $initial_version" HEAD~1 || true

  # Copy the project files to this test directory
  cp -r "$SCRIPT_DIR"/src .
  cp -r "$SCRIPT_DIR"/.github .
  cp "$SCRIPT_DIR"/package.json .
  cp "$SCRIPT_DIR"/bun.lockb . 2>/dev/null || true

  # Run act with the test event
  echo "  Running act..." | tee -a "$RESULT_FILE"

  mkdir -p "$ACT_LOGS"
  local log_file="$ACT_LOGS/${test_name}.log"

  if act push --rm -j test -j bump-version > "$log_file" 2>&1; then
    local exit_code=$?
    echo "  Act exit code: $exit_code" | tee -a "$RESULT_FILE"

    # Check if test passed
    if grep -q "Job succeeded" "$log_file"; then
      echo "  ✓ PASSED: Job succeeded" | tee -a "$RESULT_FILE"

      # Check if version was bumped correctly
      if grep -q "$expected_version" "$log_file"; then
        echo "  ✓ PASSED: Found expected version $expected_version" | tee -a "$RESULT_FILE"
      else
        echo "  ✗ FAILED: Expected version $expected_version not found in output" | tee -a "$RESULT_FILE"
        echo "  Output:" | tee -a "$RESULT_FILE"
        tail -n 20 "$log_file" | tee -a "$RESULT_FILE"
      fi
    else
      echo "  ✗ FAILED: Job did not succeed" | tee -a "$RESULT_FILE"
      echo "  Output:" | tee -a "$RESULT_FILE"
      tail -n 30 "$log_file" | tee -a "$RESULT_FILE"
    fi
  else
    echo "  ✗ FAILED: Act command failed" | tee -a "$RESULT_FILE"
    tail -n 30 "$log_file" | tee -a "$RESULT_FILE"
  fi

  echo "" | tee -a "$RESULT_FILE"
  echo "---" | tee -a "$RESULT_FILE"
  echo "" | tee -a "$RESULT_FILE"

  # Cleanup
  cd /
  rm -rf "$test_dir"
}

# Run test cases
run_test_case "Test 1: Patch bump (fix commit)" "1.0.0" "1.0.1" "patch"
run_test_case "Test 2: Minor bump (feat commit)" "1.0.0" "1.1.0" "minor"
run_test_case "Test 3: Major bump (breaking change)" "1.0.0" "2.0.0" "major"

# Validate workflow file
echo "[VALIDATION] Checking workflow file structure" | tee -a "$RESULT_FILE"

if [ -f "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" ]; then
  echo "  ✓ Workflow file exists" | tee -a "$RESULT_FILE"

  # Check for required keys
  if grep -q "name: Semantic Version Bumper" "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"; then
    echo "  ✓ Workflow name correct" | tee -a "$RESULT_FILE"
  fi

  if grep -q "on:" "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"; then
    echo "  ✓ Trigger events defined" | tee -a "$RESULT_FILE"
  fi

  if grep -q "jobs:" "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"; then
    echo "  ✓ Jobs defined" | tee -a "$RESULT_FILE"
  fi

  if grep -q "uses: actions/checkout@v4" "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"; then
    echo "  ✓ Checkout action pinned to v4" | tee -a "$RESULT_FILE"
  fi
else
  echo "  ✗ Workflow file not found" | tee -a "$RESULT_FILE"
  exit 1
fi

# Validate with actionlint
echo "" | tee -a "$RESULT_FILE"
echo "[VALIDATION] Running actionlint" | tee -a "$RESULT_FILE"

if actionlint "$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml" 2>&1 | tee -a "$RESULT_FILE"; then
  echo "  ✓ actionlint passed" | tee -a "$RESULT_FILE"
else
  echo "  ✗ actionlint failed" | tee -a "$RESULT_FILE"
fi

echo "" | tee -a "$RESULT_FILE"
echo "======================================" | tee -a "$RESULT_FILE"
echo "Tests completed at $(date)" | tee -a "$RESULT_FILE"

echo ""
echo "Test results saved to: $RESULT_FILE"
cat "$RESULT_FILE"
