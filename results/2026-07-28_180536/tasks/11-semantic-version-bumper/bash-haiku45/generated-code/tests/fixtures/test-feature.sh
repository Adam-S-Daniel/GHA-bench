#!/usr/bin/env bash
# Test fixture: Feature commit resulting in minor version bump

set -e

echo "=== TEST: Feature commit - minor version bump ==="

# Setup
git init test-feature-repo
cd test-feature-repo
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial version
echo "2.3.1" > VERSION
git add VERSION
git commit -m "initial: setup version"

# Add a feature commit
git commit --allow-empty -m "feat: add user authentication module"

# Test next version
echo "Testing next version calculation..."
next=$(../../../semantic-version-bumper.sh --next-version VERSION)
if [[ "$next" == "2.4.0" ]]; then
  echo "✓ Next version: $next (minor bump)"
else
  echo "✗ Expected 2.4.0, got $next"
  exit 1
fi

echo "✓ Test passed"
