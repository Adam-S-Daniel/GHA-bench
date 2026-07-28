#!/usr/bin/env bats
# Test suite for updating version in files

load test_helper

source ./semantic-version-bumper.sh

@test "update_version: updates version.txt" {
  echo "1.2.3" > "$TEST_TMPDIR/version.txt"

  update_version "$TEST_TMPDIR/version.txt" "1.2.4"

  result=$(cat "$TEST_TMPDIR/version.txt")
  [ "$result" = "1.2.4" ]
}

@test "update_version: updates package.json version" {
  cat > "$TEST_TMPDIR/package.json" <<'EOF'
{
  "name": "test-app",
  "version": "1.2.3",
  "description": "test"
}
EOF

  update_version "$TEST_TMPDIR/package.json" "1.2.4"

  result=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEST_TMPDIR/package.json" | grep -o '[0-9]\.[0-9]\.[0-9]')
  [ "$result" = "1.2.4" ]
}

@test "update_version: preserves json formatting in package.json" {
  cat > "$TEST_TMPDIR/package.json" <<'EOF'
{
  "name": "test-app",
  "version": "1.2.3"
}
EOF

  update_version "$TEST_TMPDIR/package.json" "2.0.0"

  # Should still be valid JSON
  jq . "$TEST_TMPDIR/package.json" > /dev/null
}

@test "update_version: handles missing file" {
  run update_version "/nonexistent/version.txt" "1.2.4"

  [ "$status" -ne 0 ]
}

@test "update_version: preserves other content in version.txt" {
  cat > "$TEST_TMPDIR/version.txt" <<'EOF'
1.2.3
# This is a comment
EOF

  update_version "$TEST_TMPDIR/version.txt" "1.3.0"

  [ "$(head -n 1 "$TEST_TMPDIR/version.txt")" = "1.3.0" ]
  [ "$(tail -n 1 "$TEST_TMPDIR/version.txt")" = "# This is a comment" ]
}
