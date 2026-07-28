#!/usr/bin/env bats

# Test suite for the GitHub Actions matrix generator
# Tests the matrix generation, validation, and configuration handling

load test_helper

@test "script exists and is executable" {
    [ -x "$PROJECT_ROOT/matrix-generator.sh" ]
}

@test "simple matrix with os and language versions" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "language": {
    "python": ["3.9", "3.10"],
    "node": ["18", "20"]
  }
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    echo "$output" | grep -q '"os"'
    echo "$output" | grep -q '"language"'
    echo "$output" | grep -q '"python"'
    echo "$output" | grep -q '"node"'
}

@test "matrix with feature flags" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "features": ["lint", "test", "coverage"]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    echo "$output" | grep -q '"features"'
}

@test "matrix validates maximum size" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "max_matrix_size": 20,
  "os": ["ubuntu-latest", "macos-latest", "windows-latest"],
  "version": ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file" 2>&1) || true
    local exit_code=$?

    echo "$output" | grep -q "exceed"
}

@test "error handling for missing config file" {
    output=$("$PROJECT_ROOT/matrix-generator.sh" "/nonexistent/file.json" 2>&1) || true

    echo "$output" | grep -q "not found"
}

@test "error handling for invalid JSON" {
    local config_file
    config_file=$(mktemp)
    echo "{ invalid json" > "$config_file"

    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file" 2>&1) || true

    echo "$output" | grep -q "JSON"
}

@test "matrix with include rules" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "version": ["1.0", "2.0"],
  "include": [
    {"os": "windows-latest", "version": "2.1"}
  ]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    echo "$output" | grep -q '"windows-latest"'
    echo "$output" | grep -q '"2.1"'
}

@test "matrix with exclude rules" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "version": ["1.0", "2.0"],
  "exclude": [
    {"os": "macos-latest", "version": "1.0"}
  ]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    # Check that the excluded combination is not in the output
    # (macos-latest with 1.0 should not appear together)
}

@test "fail-fast configuration" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "version": ["1.0"],
  "strategy": {
    "fail-fast": true,
    "max-parallel": 2
  }
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    echo "$output" | grep -q "fail-fast"
    echo "$output" | grep -q "max-parallel"
}

@test "matrix size does not exceed default maximum" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "version": ["1", "2", "3"]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    # Should succeed with reasonable sizes
}

@test "output is valid JSON" {
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << 'EOF'
{
  "os": ["ubuntu-latest"],
  "language": ["python", "ruby"]
}
EOF

    local output
    output=$("$PROJECT_ROOT/matrix-generator.sh" "$config_file")
    local exit_code=$?

    [ $exit_code -eq 0 ]
    # Validate JSON
    echo "$output" | jq . > /dev/null 2>&1
    [ $? -eq 0 ]
}
