#!/bin/bash
# Test harness to validate version bumper through full workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

# Test result capture
RESULT_FILE="test-results.json"
{
  echo "["
} > "$RESULT_FILE"

test_case() {
  local name=$1
  local fixture=$2
  local expected_version=$3
  local initial_version=$4

  echo -e "${YELLOW}Testing: $name${NC}"

  # Create temp directory for this test
  local test_dir=$(mktemp -d)
  cd "$test_dir"

  # Initialize git repo
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial package.json
  cat > package.json <<EOF
{
  "name": "test-app",
  "version": "$initial_version"
}
EOF

  # Create a dummy file and commit to establish history
  echo "initial" > README.md
  git add README.md
  git commit -m "Initial commit"

  # Add commits based on fixture
  if [ -f "../fixtures/$fixture" ]; then
    while IFS= read -r message; do
      if [ -n "$message" ]; then
        # Create a dummy change
        echo "change" >> dummy.txt
        git add dummy.txt
        git commit -m "$message" 2>/dev/null || true
      fi
    done < "../fixtures/$fixture"
  fi

  # Run the bumper (would use CLI in real scenario)
  # For now, test the library directly through bun
  cd "$test_dir"
  bun run ../cli.ts bump --fixture "../fixtures/$fixture" > output.json 2>&1 || true

  # Parse the output
  if [ -f output.json ]; then
    actual_version=$(jq -r '.newVersion' output.json 2>/dev/null || echo "ERROR")

    if [ "$actual_version" = "$expected_version" ]; then
      echo -e "${GREEN}✓ PASS: Got expected version $expected_version${NC}"
      ((PASS_COUNT++))

      # Add to results
      sed '$ d' "$RESULT_FILE" > "$RESULT_FILE.tmp" && mv "$RESULT_FILE.tmp" "$RESULT_FILE"
      cat >> "$RESULT_FILE" <<EOF
  {
    "test": "$name",
    "fixture": "$fixture",
    "status": "PASS",
    "expected_version": "$expected_version",
    "actual_version": "$actual_version"
  },
EOF
    else
      echo -e "${RED}✗ FAIL: Expected $expected_version but got $actual_version${NC}"
      ((FAIL_COUNT++))

      sed '$ d' "$RESULT_FILE" > "$RESULT_FILE.tmp" && mv "$RESULT_FILE.tmp" "$RESULT_FILE"
      cat >> "$RESULT_FILE" <<EOF
  {
    "test": "$name",
    "fixture": "$fixture",
    "status": "FAIL",
    "expected_version": "$expected_version",
    "actual_version": "$actual_version"
  },
EOF
    fi
  else
    echo -e "${RED}✗ FAIL: Could not run test${NC}"
    ((FAIL_COUNT++))
  fi

  # Cleanup
  cd /
  rm -rf "$test_dir"
}

# Run test cases
echo "Running version bumper tests..."
echo

test_case "Patch bump (fixes only)" "commits-patch.txt" "1.0.1" "1.0.0"
test_case "Minor bump (features)" "commits-minor.txt" "1.1.0" "1.0.0"
test_case "Major bump (breaking)" "commits-major.txt" "2.0.0" "1.0.0"

# Close JSON array
sed '$ s/,$//' "$RESULT_FILE" > "$RESULT_FILE.tmp" && mv "$RESULT_FILE.tmp" "$RESULT_FILE"
echo "]" >> "$RESULT_FILE"

# Summary
echo
echo "======================================"
echo -e "Tests passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Tests failed: ${RED}$FAIL_COUNT${NC}"
echo "======================================"

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
fi
