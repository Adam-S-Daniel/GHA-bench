#!/bin/bash
# Validate workflow structure and run actionlint

set -e

echo "Validating workflow structure..."
echo ""

WORKFLOW_FILE=".github/workflows/environment-matrix-generator.yml"

# Check file exists
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "❌ Workflow file not found: $WORKFLOW_FILE"
    exit 1
fi
echo "✅ Workflow file exists"

# Check required fields with grep (simple validation)
if ! grep -q "^name:" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'name' field"
    exit 1
fi
echo "✅ Workflow has 'name' field"

if ! grep -q "^on:" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'on' field"
    exit 1
fi
echo "✅ Workflow has 'on' field (triggers)"

if ! grep -q "^jobs:" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'jobs' field"
    exit 1
fi
echo "✅ Workflow has 'jobs' field"

# Check for key steps
if ! grep -q "Checkout code" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'Checkout code' step"
    exit 1
fi
echo "✅ Workflow has 'Checkout code' step"

if ! grep -q "Setup Bun" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'Setup Bun' step"
    exit 1
fi
echo "✅ Workflow has 'Setup Bun' step"

if ! grep -q "Run unit tests" "$WORKFLOW_FILE"; then
    echo "❌ Missing 'Run unit tests' step"
    exit 1
fi
echo "✅ Workflow has 'Run unit tests' step"

# Check required files exist
echo ""
echo "Verifying required files exist:"
for file in matrix.ts cli.ts matrix.test.ts cli.test.ts package.json; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ Missing: $file"
        exit 1
    fi
done

# Run actionlint
echo ""
echo "Running actionlint..."
if actionlint "$WORKFLOW_FILE"; then
    echo "✅ actionlint passed"
else
    echo "❌ actionlint failed"
    exit 1
fi

echo ""
echo "✅ All workflow validations passed!"
