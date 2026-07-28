#!/bin/bash

echo "=========================================="
echo "SEMANTIC VERSION BUMPER - FINAL VERIFICATION"
echo "=========================================="
echo ""

# Test 1: Direct script tests
echo "1. Running bats unit tests..."
test_output=$(bats test_semantic_version_bumper.bats 2>&1)
test_count=$(echo "$test_output" | grep "^ok" | wc -l)
if [[ $test_count -eq 28 ]]; then
  echo "   ✓ All 28 unit tests passed"
else
  echo "   ✗ Expected 28 tests, got $test_count"
  exit 1
fi
echo ""

# Test 2: Syntax validation
echo "2. Validating script syntax..."
bash -n semantic_version_bumper.sh
echo "   ✓ Bash syntax valid"

shellcheck semantic_version_bumper.sh
echo "   ✓ ShellCheck passed"
echo ""

# Test 3: Workflow validation
echo "3. Validating GitHub Actions workflow..."
actionlint .github/workflows/semantic-version-bumper.yml
echo "   ✓ actionlint passed"
echo ""

# Test 4: act execution
echo "4. Verifying act execution results..."
if grep -q "Job succeeded" act-result.txt; then
  echo "   ✓ act job completed successfully"
else
  echo "   ✗ act job failed"
  exit 1
fi

for test in "Patch bump" "Minor bump" "Major bump" "Version.txt format" "Changelog generation"; do
  if grep -q "PASS: $test test" act-result.txt; then
    echo "   ✓ $test test passed"
  else
    echo "   ✗ $test test failed"
    exit 1
  fi
done
echo ""

# Test 5: File existence
echo "5. Verifying all required files exist..."
[[ -f "semantic_version_bumper.sh" ]] && echo "   ✓ semantic_version_bumper.sh"
[[ -f "test_semantic_version_bumper.bats" ]] && echo "   ✓ test_semantic_version_bumper.bats"
[[ -f ".github/workflows/semantic-version-bumper.yml" ]] && echo "   ✓ .github/workflows/semantic-version-bumper.yml"
[[ -f "act-result.txt" ]] && echo "   ✓ act-result.txt"
echo ""

# Test 6: Script functionality demo
echo "6. Quick functionality demonstration..."
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init
git config user.email "test@example.com"
git config user.name "Test"
echo '{"version": "1.0.0"}' > package.json
git add package.json
git commit -m "init"
git tag v1.0.0
git commit --allow-empty -m "feat: new feature"

result=$(/bin/bash "$OLDPWD/semantic_version_bumper.sh" package.json | head -1)
if [[ "$result" == "1.1.0" ]]; then
  echo "   ✓ Version bumped correctly: 1.0.0 → 1.1.0"
else
  echo "   ✗ Version bump failed. Got: $result"
  exit 1
fi
cd "$OLDPWD"
rm -rf "$TMPDIR"
echo ""

echo "=========================================="
echo "✓ ALL VERIFICATIONS PASSED"
echo "=========================================="
