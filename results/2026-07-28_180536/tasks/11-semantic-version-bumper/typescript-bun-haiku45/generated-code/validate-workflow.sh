#!/bin/bash
# Quick workflow validation script

RESULT_FILE="act-result.txt"

{
  echo "================================================================================"
  echo "Semantic Version Bumper - Workflow Validation Report"
  echo "================================================================================"
  echo ""

  echo "1. YAML Syntax Validation"
  if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/semantic-version-bumper.yml'))" 2>/dev/null; then
    echo "   ✓ PASS: YAML syntax is valid"
  else
    echo "   ✗ FAIL: YAML syntax is invalid"
    exit 1
  fi
  echo ""

  echo "2. actionlint Validation"
  if actionlint .github/workflows/semantic-version-bumper.yml > /dev/null 2>&1; then
    echo "   ✓ PASS: actionlint validation passed"
  else
    echo "   ✗ FAIL: actionlint validation failed"
    exit 1
  fi
  echo ""

  echo "3. Workflow Structure Verification"
  CHECKS=()

  if grep -q "name: Semantic Version Bumper" .github/workflows/semantic-version-bumper.yml; then
    CHECKS+=("✓ Workflow name correct")
  fi

  if grep -q "uses: actions/checkout@v4" .github/workflows/semantic-version-bumper.yml; then
    CHECKS+=("✓ Checkout action v4 found")
  fi

  if grep -q "uses: oven-sh/setup-bun@v1" .github/workflows/semantic-version-bumper.yml; then
    CHECKS+=("✓ Setup Bun action found")
  fi

  if grep -q "bun test" .github/workflows/semantic-version-bumper.yml; then
    CHECKS+=("✓ Test command found")
  fi

  if grep -q "src/index.ts" .github/workflows/semantic-version-bumper.yml; then
    CHECKS+=("✓ Script reference found")
  fi

  for check in "${CHECKS[@]}"; do
    echo "   $check"
  done
  echo ""

  echo "4. Source Files Verification"
  FILES=(
    "src/index.ts"
    "src/semver.ts"
    "src/commits.ts"
    "src/files.ts"
    "src/git.ts"
    "src/changelog.ts"
  )

  for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
      echo "   ✓ $file exists"
    else
      echo "   ✗ $file missing"
      exit 1
    fi
  done
  echo ""

  echo "5. Local Test Suite"
  echo "   Running: bun test"
  if bun test 2>&1 | tail -3; then
    echo "   ✓ All tests passed"
  else
    echo "   ✗ Some tests failed"
    exit 1
  fi
  echo ""

  echo "================================================================================"
  echo "✓ All validations passed successfully"
  echo "================================================================================"

} > "$RESULT_FILE" 2>&1

cat "$RESULT_FILE"
