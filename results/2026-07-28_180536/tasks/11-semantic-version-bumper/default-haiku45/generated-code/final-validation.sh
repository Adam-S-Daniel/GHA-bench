#!/bin/bash
echo "=== FINAL VALIDATION ===="
echo ""

echo "1. File Structure:"
files=(
  "src/semantic-version-bumper.js"
  "bin/bump-version.js"
  "__tests__/semantic-version-bumper.test.js"
  ".github/workflows/semantic-version-bumper.yml"
  "package.json"
  "README.md"
  "run-act-tests.sh"
  "fixtures/test-case-1-patch-bump.json"
  "fixtures/test-case-2-minor-bump.json"
  "fixtures/test-case-3-major-bump.json"
  "act-result.txt"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ $file"
  else
    echo "  ✗ $file (MISSING)"
  fi
done

echo ""
echo "2. Unit Tests:"
npm test 2>&1 | grep -E "Test Suites:|Tests:|PASS|FAIL"

echo ""
echo "3. Workflow Validation:"
if actionlint .github/workflows/semantic-version-bumper.yml 2>&1 | grep -q "^$"; then
  echo "  ✓ actionlint passes"
else
  echo "  ⚠ actionlint issues found"
  actionlint .github/workflows/semantic-version-bumper.yml
fi

echo ""
echo "4. act-result.txt Content Summary:"
if [ -f "act-result.txt" ]; then
  echo "  ✓ act-result.txt exists"
  echo "  - Lines: $(wc -l < act-result.txt)"
  echo "  - Includes workflow structure validation: $(grep -c 'Workflow structure validation' act-result.txt)"
  echo "  - Includes actionlint validation: $(grep -c 'actionlint' act-result.txt)"
  echo "  - Includes unit test results: $(grep -c 'Test Suites.*passed' act-result.txt)"
  echo "  - Includes act job execution: $(grep -c 'Job succeeded' act-result.txt)"
fi

echo ""
echo "=== VALIDATION COMPLETE ==="
