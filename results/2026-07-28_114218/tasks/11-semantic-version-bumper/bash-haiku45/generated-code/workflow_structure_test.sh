#!/bin/bash

set -e

WORKFLOW_FILE=".github/workflows/semantic-version-bumper.yml"

echo "=== Workflow Structure Validation ==="

# 1. Check file exists
if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "FAIL: Workflow file not found: $WORKFLOW_FILE"
  exit 1
fi
echo "✓ Workflow file exists"

# 2. Validate YAML with actionlint
if ! actionlint "$WORKFLOW_FILE"; then
  echo "FAIL: actionlint validation failed"
  exit 1
fi
echo "✓ actionlint validation passed"

# 3. Check required triggers
for trigger in "push" "pull_request" "workflow_dispatch"; do
  if ! grep -q "$trigger:" "$WORKFLOW_FILE"; then
    echo "FAIL: Missing trigger: $trigger"
    exit 1
  fi
done
echo "✓ All required triggers present"

# 4. Check job exists
if ! grep -q "^jobs:" "$WORKFLOW_FILE"; then
  echo "FAIL: Missing jobs section"
  exit 1
fi
echo "✓ Jobs section present"

# 5. Check steps exist
if ! grep -q "steps:" "$WORKFLOW_FILE"; then
  echo "FAIL: Missing steps section"
  exit 1
fi
echo "✓ Steps section present"

# 6. Check script file is referenced correctly
if ! grep -q "semantic_version_bumper.sh" "$WORKFLOW_FILE"; then
  echo "FAIL: Script not referenced in workflow"
  exit 1
fi
if [[ ! -f "semantic_version_bumper.sh" ]]; then
  echo "FAIL: Script file not found"
  exit 1
fi
echo "✓ Script file referenced and exists"

# 7. Check test file is referenced correctly
if ! grep -q "test_semantic_version_bumper.bats" "$WORKFLOW_FILE"; then
  echo "FAIL: Test file not referenced in workflow"
  exit 1
fi
if [[ ! -f "test_semantic_version_bumper.bats" ]]; then
  echo "FAIL: Test file not found"
  exit 1
fi
echo "✓ Test file referenced and exists"

# 8. Check permissions
if ! grep -q "permissions:" "$WORKFLOW_FILE"; then
  echo "FAIL: Missing permissions section"
  exit 1
fi
echo "✓ Permissions section present"

# 9. Check checkout action
if ! grep -q "actions/checkout@v4" "$WORKFLOW_FILE"; then
  echo "FAIL: Missing or incorrect checkout action"
  exit 1
fi
echo "✓ Checkout action present"

echo ""
echo "=== All Structure Tests Passed ==="
