#!/usr/bin/env bash
# Test fixture: Basic version parsing and patch bump

set -e

echo "=== TEST: Basic version parsing and patch bump ==="

# Setup
git init test-basic-repo
cd test-basic-repo
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial version
echo "1.0.0" > VERSION
git add VERSION
git commit -m "initial: setup version"

# Add a fix commit
git commit --allow-empty -m "fix: resolve parsing bug"

# Test current version
echo "Testing current version parsing..."
current=$(../../../semantic-version-bumper.sh --current-version VERSION)
if [[ "$current" == "1.0.0" ]]; then
  echo "✓ Current version: $current"
else
  echo "✗ Expected 1.0.0, got $current"
  exit 1
fi

# Test next version
echo "Testing next version calculation..."
next=$(../../../semantic-version-bumper.sh --next-version VERSION)
if [[ "$next" == "1.0.1" ]]; then
  echo "✓ Next version: $next (patch bump)"
else
  echo "✗ Expected 1.0.1, got $next"
  exit 1
fi

echo "✓ Test passed"
