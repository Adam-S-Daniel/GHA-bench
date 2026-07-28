#!/bin/bash

# Test fixture validation script
# Tests the matrix generator CLI against all test fixtures

set -e

echo "=== Matrix Generator Fixture Tests ==="
echo

test_fixture() {
    local fixture=$1
    local expected_count=$2
    local test_name=$3

    echo "Testing: $test_name"
    echo "  Config: $fixture"

    output=$(bun matrix.ts "$fixture" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "  ❌ FAILED: Exit code $exit_code"
        echo "$output"
        return 1
    fi

    # Extract count of combinations
    count=$(echo "$output" | python3 -c "import json, sys; data=json.load(sys.stdin); print(len(data['matrix']['include']))")

    if [ "$count" = "$expected_count" ]; then
        echo "  ✓ PASSED: Generated $count combinations"
    else
        echo "  ❌ FAILED: Expected $expected_count combinations, got $count"
        return 1
    fi
    echo
}

test_fixture "fixtures/simple-config.json" "4" "Simple config (2 os × 2 languages)"
test_fixture "fixtures/exclude-only.json" "7" "Exclude rules (3 os × 3 languages - 2 excludes)"
test_fixture "fixtures/include-only.json" "3" "Include rules (1 cartesian + 2 includes)"
test_fixture "fixtures/single-axis.json" "3" "Single axis (3 os)"

echo "=== Error Handling Tests ==="
echo

# Test: File not found
echo "Testing: File not found"
if bun matrix.ts "nonexistent.json" 2>&1 | grep -q "Error"; then
    echo "  ✓ PASSED: Proper error for missing file"
else
    echo "  ❌ FAILED: Should error on missing file"
    exit 1
fi
echo

# Test: Invalid JSON
echo "Testing: Invalid JSON"
echo '{ invalid json }' > /tmp/invalid.json
if bun matrix.ts /tmp/invalid.json 2>&1 | grep -q "Error"; then
    echo "  ✓ PASSED: Proper error for invalid JSON"
else
    echo "  ❌ FAILED: Should error on invalid JSON"
    exit 1
fi
rm /tmp/invalid.json
echo

# Test: Missing required fields
echo "Testing: Missing required fields"
echo '{ "os": [] }' > /tmp/incomplete.json
if bun matrix.ts /tmp/incomplete.json 2>&1 | grep -q "Error"; then
    echo "  ✓ PASSED: Proper error for missing 'languages' field"
else
    echo "  ❌ FAILED: Should error on missing 'languages' field"
    exit 1
fi
rm /tmp/incomplete.json
echo

# Test: MaxSize exceeded
echo "Testing: MaxSize exceeded"
cat > /tmp/oversized.json << 'EOF'
{
  "os": ["a", "b", "c", "d"],
  "languages": ["x", "y", "z"],
  "maxSize": 5
}
EOF
if bun matrix.ts /tmp/oversized.json 2>&1 | grep -q "exceeds maximum"; then
    echo "  ✓ PASSED: Proper error for exceeding maxSize"
else
    echo "  ❌ FAILED: Should error when matrix size exceeds maximum"
    exit 1
fi
rm /tmp/oversized.json
echo

echo "=== All fixture tests passed! ==="
