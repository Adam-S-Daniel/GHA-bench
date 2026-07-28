#!/usr/bin/env bats

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_GIT_DIR="$TEST_TEMP_DIR/test-repo"
  mkdir -p "$TEST_GIT_DIR"
  cd "$TEST_GIT_DIR"

  # Initialize git repo
  git init
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Source the version bumper script
  source "$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/version-bumper.sh"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "parse_version extracts major.minor.patch from version string" {
  local version="1.2.3"
  declare -n result=parsed_version
  parse_version "$version"

  [[ "${parsed_version[major]}" == "1" ]]
  [[ "${parsed_version[minor]}" == "2" ]]
  [[ "${parsed_version[patch]}" == "3" ]]
}

@test "parse_version rejects invalid version format" {
  run parse_version "1.2"
  [ $status -eq 1 ]
}

@test "get_commit_type identifies feat commits as minor" {
  local commit_type=$(get_commit_type "feat: add new feature")
  [[ "$commit_type" == "minor" ]]
}

@test "get_commit_type identifies fix commits as patch" {
  local commit_type=$(get_commit_type "fix: resolve bug")
  [[ "$commit_type" == "patch" ]]
}

@test "get_commit_type identifies breaking changes as major" {
  local commit_type=$(get_commit_type "feat!: breaking change")
  [[ "$commit_type" == "major" ]]
}

@test "get_commit_type identifies BREAKING CHANGE in body as major" {
  local commit_msg="feat: some feature

BREAKING CHANGE: this breaks compatibility"
  local commit_type=$(get_commit_type "$commit_msg")
  [[ "$commit_type" == "major" ]]
}

@test "bump_version increments patch for patch bump" {
  local new_version=$(bump_version "1.2.3" "patch")
  [[ "$new_version" == "1.2.4" ]]
}

@test "bump_version increments minor for minor bump and resets patch" {
  local new_version=$(bump_version "1.2.3" "minor")
  [[ "$new_version" == "1.3.0" ]]
}

@test "bump_version increments major for major bump and resets minor and patch" {
  local new_version=$(bump_version "1.2.3" "major")
  [[ "$new_version" == "2.0.0" ]]
}

@test "read_version_from_package_json reads version from package.json" {
  echo '{"version":"2.1.0","name":"test"}' > "$TEST_GIT_DIR/package.json"
  local version=$(read_version_from_package_json "$TEST_GIT_DIR/package.json")
  [[ "$version" == "2.1.0" ]]
}

@test "get_highest_bump_type returns major when both major and minor present" {
  local bump=$(get_highest_bump_type "major" "minor")
  [[ "$bump" == "major" ]]
}

@test "get_highest_bump_type returns minor when minor and patch present" {
  local bump=$(get_highest_bump_type "minor" "patch")
  [[ "$bump" == "minor" ]]
}

@test "get_conventional_commits finds feat commits in git log" {
  cd "$TEST_GIT_DIR"
  echo "test content" > test.txt
  git add test.txt
  git commit -m "feat: add test feature"
  git commit --allow-empty -m "fix: fix a bug"

  local commits=$(get_conventional_commits)
  [[ "$commits" == *"feat"* ]]
  [[ "$commits" == *"fix"* ]]
}

@test "generate_changelog creates formatted changelog entry" {
  cd "$TEST_GIT_DIR"
  echo "content" > file.txt
  git add file.txt
  git commit -m "feat: new feature"

  local changelog=$(generate_changelog "1.0.0" "1.1.0")
  [[ "$changelog" == *"1.1.0"* ]]
  [[ "$changelog" == *"feat"* ]]
}

@test "write_version_to_package_json updates package.json version" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  write_version_to_package_json "package.json" "1.1.0"

  local version=$(read_version_from_package_json "package.json")
  [[ "$version" == "1.1.0" ]]
}

# Integration tests for the main entry point
@test "semantic-version-bumper.sh bumps version with feat commit" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  git add package.json
  git commit -m "initial"

  echo "feature code" > feature.js
  git add feature.js
  git commit -m "feat: add new feature"

  local new_version
  new_version=$("$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/semantic-version-bumper.sh" -f package.json)
  [[ "$new_version" == "1.1.0" ]]

  local updated_version=$(read_version_from_package_json "package.json")
  [[ "$updated_version" == "1.1.0" ]]
}

@test "semantic-version-bumper.sh bumps version with fix commit" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  git add package.json
  git commit -m "initial"

  echo "bug fix" > bug.js
  git add bug.js
  git commit -m "fix: resolve critical bug"

  local new_version
  new_version=$("$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/semantic-version-bumper.sh" -f package.json)
  [[ "$new_version" == "1.0.1" ]]
}

@test "semantic-version-bumper.sh bumps version with breaking change" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  git add package.json
  git commit -m "initial"

  echo "breaking" > breaking.js
  git add breaking.js
  git commit -m "feat!: breaking API change"

  local new_version
  new_version=$("$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/semantic-version-bumper.sh" -f package.json)
  [[ "$new_version" == "2.0.0" ]]
}

@test "semantic-version-bumper.sh dry-run doesn't modify files" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  git add package.json
  git commit -m "initial"

  echo "feature" > feature.js
  git add feature.js
  git commit -m "feat: add feature"

  "$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/semantic-version-bumper.sh" --dry-run -f package.json >/dev/null

  local version=$(read_version_from_package_json "package.json")
  [[ "$version" == "1.0.0" ]]
}

@test "semantic-version-bumper.sh creates changelog" {
  cd "$TEST_GIT_DIR"
  echo '{"version":"1.0.0","name":"test"}' > package.json
  git add package.json
  git commit -m "initial"

  echo "feature" > feature.js
  git add feature.js
  git commit -m "feat: add feature"

  "$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/semantic-version-bumper.sh" -f package.json >/dev/null

  [[ -f "CHANGELOG.md" ]]
  grep -q "1.1.0" CHANGELOG.md
}
