#!/bin/bash

# Mock test fixtures for commit logs and version scenarios
# These fixtures are used for manual testing and documentation

create_fixture_patch_scenario() {
  cat > test-fixture-patch.txt << 'EOF'
Fixture: Patch Version Bump Scenario
====================================

Initial State:
  - Current version: 1.0.0
  - Version file: package.json

Commits since last release:
  1. fix: correct null pointer exception in parser
  2. fix: update documentation links
  3. chore: update dependencies

Expected Behavior:
  - Analyze commits: only fix commits → bump type = patch
  - Current version: 1.0.0
  - Next version: 1.0.1

Changelog Entry:
  ### Bug Fixes
  - correct null pointer exception in parser
  - update documentation links
EOF
  cat test-fixture-patch.txt
}

create_fixture_minor_scenario() {
  cat > test-fixture-minor.txt << 'EOF'
Fixture: Minor Version Bump Scenario
====================================

Initial State:
  - Current version: 2.0.0
  - Version file: VERSION

Commits since last release:
  1. feat: add OAuth2 authentication support
  2. fix: memory leak in cache eviction
  3. feat: add API rate limiting
  4. docs: add authentication guide

Expected Behavior:
  - Analyze commits: feat commits exist → bump type = minor
  - Current version: 2.0.0
  - Next version: 2.1.0

Changelog Entry:
  ### Features
  - add OAuth2 authentication support
  - add API rate limiting

  ### Bug Fixes
  - memory leak in cache eviction
EOF
  cat test-fixture-minor.txt
}

create_fixture_major_scenario() {
  cat > test-fixture-major.txt << 'EOF'
Fixture: Major Version Bump Scenario (Breaking Change)
======================================================

Initial State:
  - Current version: 1.5.3
  - Version file: package.json

Commits since last release:
  1. feat!: redesign REST API endpoints
  2. feat: add websocket support
  3. fix: correct response encoding
  4. docs: API migration guide

Expected Behavior:
  - Analyze commits: breaking change (feat!) → bump type = major
  - Current version: 1.5.3
  - Next version: 2.0.0
  - Reset minor and patch versions to 0

Changelog Entry:
  ### Breaking Changes
  - redesign REST API endpoints

  ### Features
  - add websocket support

  ### Bug Fixes
  - correct response encoding
EOF
  cat test-fixture-major.txt
}

create_fixture_json_version() {
  cat > test-fixture-package.json << 'EOF'
{
  "name": "semantic-version-bumper",
  "version": "1.0.0",
  "description": "Automatic semantic version management from conventional commits",
  "main": "version-bumper.sh",
  "scripts": {
    "test": "bash test-version-bumper.sh",
    "test:workflow": "bash test-workflow-structure.sh"
  },
  "keywords": ["semantic-versioning", "conventional-commits", "automation"],
  "author": "DevOps Team",
  "license": "MIT"
}
EOF
  cat test-fixture-package.json
}

create_fixture_text_version() {
  cat > test-fixture-VERSION.txt << 'EOF'
1.0.0
EOF
  cat test-fixture-VERSION.txt
}

create_fixture_conventional_commits() {
  cat > test-fixture-commits.txt << 'EOF'
Conventional Commit Examples
=============================

PATCH Commits (Bump minor.patch):
  fix: correct memory leak in cache
  fix: update dependency versions
  perf: optimize query performance

MINOR Commits (Bump version):
  feat: add user authentication system
  feat: support for custom themes
  feat: add export to CSV functionality

MAJOR/BREAKING Commits (Bump major):
  feat!: redesign entire API interface
  feat(api)!: replace REST with GraphQL
  BREAKING CHANGE: removed deprecated endpoints

Valid Conventional Commit Format:
  <type>(<scope>): <subject>
  <body>
  <footer>

Types:
  - feat     : A new feature
  - fix      : A bug fix
  - docs     : Documentation only changes
  - style    : Changes that don't affect code meaning
  - refactor : Code changes that don't add/fix features
  - perf     : Code changes that improve performance
  - test     : Adding missing tests or updating tests
  - chore    : Changes to build/dependencies/ci

Breaking Change Indicators:
  - Type followed by ! (e.g., feat!:)
  - BREAKING CHANGE: in commit body
  - BREAKING-CHANGE: in commit body
EOF
  cat test-fixture-commits.txt
}

# Main
echo "Creating test fixtures..."
echo ""

echo "1. Patch Scenario:"
create_fixture_patch_scenario
echo ""

echo "2. Minor Scenario:"
create_fixture_minor_scenario
echo ""

echo "3. Major Scenario (Breaking Change):"
create_fixture_major_scenario
echo ""

echo "4. JSON Version File Example:"
create_fixture_json_version
echo ""

echo "5. Text Version File Example:"
create_fixture_text_version
echo ""

echo "6. Conventional Commits Reference:"
create_fixture_conventional_commits
echo ""

echo "Test fixtures created successfully!"
