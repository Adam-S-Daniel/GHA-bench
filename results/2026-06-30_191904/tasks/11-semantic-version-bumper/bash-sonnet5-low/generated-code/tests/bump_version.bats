#!/usr/bin/env bats
# Red/green TDD test suite for scripts/bump-version.sh
#
# Each test sets up a temp working dir with a fixture version file and a
# fixture commit-log file, invokes the script, and asserts on the exact
# emitted version / changelog / file contents.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/bump-version.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

# --- Bump detection from conventional commit messages -----------------

@test "fix commits bump the patch version" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_fix_only.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "1.2.4" ]
  [ "$(cat "${WORKDIR}/VERSION")" = "1.2.4" ]
}

@test "feat commits bump the minor version and reset patch" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_feat_only.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "1.3.0" ]
  [ "$(cat "${WORKDIR}/VERSION")" = "1.3.0" ]
}

@test "breaking change commits bump the major version and reset minor/patch" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_breaking.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
  [ "$(cat "${WORKDIR}/VERSION")" = "2.0.0" ]
}

@test "a bang after the type (feat!:) counts as a breaking change" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_bang_breaking.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "mixed commits: highest-precedence bump wins (major over minor over patch)" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_mixed.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "2.0.0" ]
}

@test "commits with no recognized conventional prefix produce no bump and exit non-zero" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_none.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 1 ]
  [[ "$output" == *"no bumpable commits"* ]]
  [ "$(cat "${WORKDIR}/VERSION")" = "1.2.3" ]
}

# --- package.json support ------------------------------------------------

@test "reads and writes the version field inside package.json" {
  cp "${FIXTURES}/package_1.0.0.json" "${WORKDIR}/package.json"
  cp "${FIXTURES}/commits_feat_only.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/package.json" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 0 ]
  [ "$output" = "1.1.0" ]
  grep -q '"version": "1.1.0"' "${WORKDIR}/package.json"
}

# --- Changelog generation -------------------------------------------------

@test "generates a changelog entry listing the commits under the new version heading" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_mixed.txt" "${WORKDIR}/commits.txt"

  "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md" >/dev/null

  grep -q "## 2.0.0" "${WORKDIR}/CHANGELOG.md"
  grep -q "feat!: drop support for legacy config format" "${WORKDIR}/CHANGELOG.md"
}

@test "prepends new changelog entries above existing ones" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_fix_only.txt" "${WORKDIR}/commits.txt"
  printf '# Changelog\n\n## 1.2.3\n\n- fix: old entry\n' > "${WORKDIR}/CHANGELOG.md"

  "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md" >/dev/null

  first_heading_line="$(grep -n '^## ' "${WORKDIR}/CHANGELOG.md" | head -n1 | cut -d: -f2-)"
  [ "$first_heading_line" = "## 1.2.4" ]
}

# --- Error handling --------------------------------------------------------

@test "errors clearly when the version file does not exist" {
  cp "${FIXTURES}/commits_fix_only.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/nope" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 1 ]
  [[ "$output" == *"version file not found"* ]]
}

@test "errors clearly when the version file contains an invalid semver" {
  echo "not-a-version" > "${WORKDIR}/VERSION"
  cp "${FIXTURES}/commits_fix_only.txt" "${WORKDIR}/commits.txt"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/commits.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid semantic version"* ]]
}

@test "errors clearly when the commits file does not exist" {
  cp "${FIXTURES}/VERSION_1.2.3" "${WORKDIR}/VERSION"

  run "$SCRIPT" --version-file "${WORKDIR}/VERSION" --commits-file "${WORKDIR}/missing.txt" --changelog-file "${WORKDIR}/CHANGELOG.md"

  [ "$status" -eq 1 ]
  [[ "$output" == *"commits file not found"* ]]
}
