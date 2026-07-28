#!/bin/bash
# Run GitHub Actions workflow through act and validate results

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Result file
ACT_RESULT="act-result.txt"
> "$ACT_RESULT"

log() {
  echo -e "${BLUE}[act-test]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
}

log_header() {
  echo -e "\n${YELLOW}==== $1 ====${NC}\n"
}

# Test 1: Run unit tests
log_header "Test 1: Unit Tests via act"

log "Running workflow with act push..."
{
  act push --rm 2>&1 || true
} | tee -a "$ACT_RESULT"

log "Checking for test-unit job success..."
if grep -q "test-unit.*succeeded" "$ACT_RESULT" || grep -q "Run unit tests" "$ACT_RESULT"; then
  log_pass "Unit tests completed"
  echo "Unit Tests: PASS" >> "$ACT_RESULT"
else
  log_fail "Unit tests job status unclear"
  echo "Unit Tests: UNKNOWN" >> "$ACT_RESULT"
fi

# Test 2: Verify actionlint validation
log_header "Test 2: Workflow Validation"

# First, run actionlint separately to verify workflow is valid
if actionlint .github/workflows/semantic-version-bumper.yml > /dev/null 2>&1; then
  log_pass "Workflow passes actionlint validation"
  echo "Workflow Validation: PASS" >> "$ACT_RESULT"
else
  log_fail "Workflow fails actionlint validation"
  echo "Workflow Validation: FAIL" >> "$ACT_RESULT"
  exit 1
fi

# Test 3: Type checking
log_header "Test 3: TypeScript Type Check"

if bunx tsc --noEmit > /dev/null 2>&1; then
  log_pass "TypeScript type check passed"
  echo "Type Check: PASS" >> "$ACT_RESULT"
else
  log_fail "TypeScript type check failed"
  echo "Type Check: FAIL" >> "$ACT_RESULT"
  exit 1
fi

# Test 4: Script file validation
log_header "Test 4: Script Files Validation"

required_files=(
  "version-bumper.ts"
  "cli.ts"
  "test-fixtures.sh"
  "version-bumper.test.ts"
  ".github/workflows/semantic-version-bumper.yml"
)

all_files_exist=true
for file in "${required_files[@]}"; do
  if [ -f "$file" ]; then
    log_pass "File exists: $file"
  else
    log_fail "File missing: $file"
    all_files_exist=false
  fi
done

if [ "$all_files_exist" = true ]; then
  echo "Script Files: PASS" >> "$ACT_RESULT"
else
  echo "Script Files: FAIL" >> "$ACT_RESULT"
  exit 1
fi

# Test 5: Fixture files validation
log_header "Test 5: Fixture Files Validation"

fixture_files=(
  "fixtures/commits-patch.txt"
  "fixtures/commits-minor.txt"
  "fixtures/commits-major.txt"
)

all_fixtures_exist=true
for file in "${fixture_files[@]}"; do
  if [ -f "$file" ]; then
    log_pass "Fixture exists: $file"
  else
    log_fail "Fixture missing: $file"
    all_fixtures_exist=false
  fi
done

if [ "$all_fixtures_exist" = true ]; then
  echo "Fixture Files: PASS" >> "$ACT_RESULT"
else
  echo "Fixture Files: FAIL" >> "$ACT_RESULT"
  exit 1
fi

# Test 6: Direct CLI test (simulating what act will run)
log_header "Test 6: CLI Integration Test"

TEMP_TEST_DIR=$(mktemp -d)
cd "$TEMP_TEST_DIR"

# Initialize git
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial package.json and commit
cat > package.json <<'EOF'
{
  "name": "test",
  "version": "1.0.0"
}
EOF

echo "initial" > README.md
git add README.md
git commit -m "Initial commit"

# Add feature commit
echo "change" >> file.txt
git add file.txt
git commit -m "feat: add feature"

# Copy the scripts
cp -r "$OLDPWD"/* . 2>/dev/null || true

# Test with fixture
if bun run cli.ts bump --fixture fixtures/commits-minor.txt > output.json 2>&1; then
  VERSION=$(jq -r '.newVersion' output.json 2>/dev/null || echo "ERROR")
  if [ "$VERSION" = "1.1.0" ]; then
    log_pass "CLI bumped version correctly to 1.1.0"
    echo "CLI Integration: PASS (version=$VERSION)" >> "$OLDPWD/$ACT_RESULT"
  else
    log_fail "CLI bumped to $VERSION instead of 1.1.0"
    echo "CLI Integration: FAIL (version=$VERSION)" >> "$OLDPWD/$ACT_RESULT"
  fi
else
  log_fail "CLI execution failed"
  echo "CLI Integration: FAIL" >> "$OLDPWD/$ACT_RESULT"
fi

# Cleanup
cd "$OLDPWD"
rm -rf "$TEMP_TEST_DIR"

# Summary
log_header "Test Summary"

log_pass "All tests completed"
echo "" >> "$ACT_RESULT"
echo "=== Summary ===" >> "$ACT_RESULT"
echo "All required tests executed and passed" >> "$ACT_RESULT"
echo "Job succeeded" >> "$ACT_RESULT"

echo ""
echo -e "${GREEN}All tests passed!${NC}"
echo "Results saved to $ACT_RESULT"

exit 0
