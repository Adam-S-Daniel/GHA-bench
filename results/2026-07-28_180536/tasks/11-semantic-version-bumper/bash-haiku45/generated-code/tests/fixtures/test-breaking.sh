#!/usr/bin/env bash
# Test fixture: Breaking change commit resulting in major version bump

set -e

echo "=== TEST: Breaking change - major version bump ==="

# Setup
git init test-breaking-repo
cd test-breaking-repo
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial version
echo "1.5.2" > VERSION
git add VERSION
git commit -m "initial: setup version"

# Add a breaking change commit
git commit --allow-empty -m "feat!: remove deprecated endpoint /api/v1/users"

# Test next version
echo "Testing next version calculation..."
next=$(../../../semantic-version-bumper.sh --next-version VERSION)
if [[ "$next" == "2.0.0" ]]; then
  echo "✓ Next version: $next (major bump)"
else
  echo "✗ Expected 2.0.0, got $next"
  exit 1
fi

echo "✓ Test passed"
