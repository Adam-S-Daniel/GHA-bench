#!/usr/bin/env bash
# Test helper utilities

# Create a temporary test directory
TEST_TMPDIR=$(mktemp -d)
export TEST_TMPDIR

# Clean up test directory after tests
cleanup() {
  [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

trap cleanup EXIT
