#!/usr/bin/env bats
# Test suite for workflow structure validation

load test_helper

@test "workflow: file exists" {
  [ -f ".github/workflows/semantic-version-bumper.yml" ]
}

@test "workflow: has correct name" {
  result=$(grep "^name:" .github/workflows/semantic-version-bumper.yml)
  [[ "$result" =~ "Semantic Version Bumper" ]]
}

@test "workflow: has push trigger" {
  grep -q "on:" .github/workflows/semantic-version-bumper.yml
  grep -q "push:" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: has pull_request trigger" {
  grep -q "pull_request:" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: has workflow_dispatch trigger" {
  grep -q "workflow_dispatch:" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: has test job" {
  grep -q "test:" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: test job runs bats" {
  grep -q "bats tests/\*\.bats" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: test job uses ubuntu-latest" {
  grep -q "ubuntu-latest" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: test job installs bats" {
  grep -q "npm install.*bats" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: references semantic-version-bumper.sh" {
  grep -q "semantic-version-bumper.sh" .github/workflows/semantic-version-bumper.yml
}

@test "workflow: passes actionlint" {
  # Only run actionlint if it's available (not in act containers)
  if command -v actionlint &> /dev/null; then
    run actionlint .github/workflows/semantic-version-bumper.yml
    [ "$status" -eq 0 ]
  else
    skip "actionlint not installed"
  fi
}
