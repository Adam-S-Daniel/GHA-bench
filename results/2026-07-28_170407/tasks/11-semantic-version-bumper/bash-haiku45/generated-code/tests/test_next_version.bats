#!/usr/bin/env bats
# Test suite for calculating the next version

load test_helper

source ./semantic-version-bumper.sh

@test "next_version: increments patch for patch bump" {
  result=$(next_version "1.2.3" "patch")
  [ "$result" = "1.2.4" ]
}

@test "next_version: increments minor and resets patch for minor bump" {
  result=$(next_version "1.2.3" "minor")
  [ "$result" = "1.3.0" ]
}

@test "next_version: increments major and resets minor/patch for major bump" {
  result=$(next_version "1.2.3" "major")
  [ "$result" = "2.0.0" ]
}

@test "next_version: handles 0.0.x versions" {
  result=$(next_version "0.0.5" "patch")
  [ "$result" = "0.0.6" ]
}

@test "next_version: handles 0.x.y versions with minor bump" {
  result=$(next_version "0.5.2" "minor")
  [ "$result" = "0.6.0" ]
}

@test "next_version: handles 0.x.y versions with major bump" {
  result=$(next_version "0.5.2" "major")
  [ "$result" = "1.0.0" ]
}

@test "next_version: returns same version for 'none' bump" {
  result=$(next_version "1.2.3" "none")
  [ "$result" = "1.2.3" ]
}

@test "next_version: rejects invalid bump type" {
  run next_version "1.2.3" "invalid"
  [ "$status" -ne 0 ]
}
