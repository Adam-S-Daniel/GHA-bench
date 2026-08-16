#!/usr/bin/env bats
# Test suite for semantic version bumper

load test_helper

source ./semantic-version-bumper.sh

@test "parse_version: extracts version from version.txt" {
  echo "1.2.3" > "$TEST_TMPDIR/version.txt"

  result=$(parse_version "$TEST_TMPDIR/version.txt")

  [ "$result" = "1.2.3" ]
}

@test "parse_version: extracts version from package.json" {
  cat > "$TEST_TMPDIR/package.json" <<'EOF'
{
  "name": "test-app",
  "version": "2.0.1"
}
EOF

  result=$(parse_version "$TEST_TMPDIR/package.json")

  [ "$result" = "2.0.1" ]
}

@test "parse_version: handles missing file gracefully" {
  run parse_version "/nonexistent/version.txt"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "Error" ]]
}

@test "parse_version: validates semantic version format" {
  echo "not-a-version" > "$TEST_TMPDIR/version.txt"

  run parse_version "$TEST_TMPDIR/version.txt"

  [ "$status" -ne 0 ]
}
