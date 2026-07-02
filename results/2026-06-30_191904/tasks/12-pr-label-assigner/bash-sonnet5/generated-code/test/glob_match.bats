#!/usr/bin/env bats
#
# Unit tests for the glob -> regex translation and path matching helpers
# in label-assigner.sh. The script is sourced (not executed) so we can
# call its internal functions directly. Sourcing is guarded in the script
# itself so `main` does not run as a side effect of sourcing.

setup() {
  SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/../label-assigner.sh"
  source "$SCRIPT_UNDER_TEST"
}

@test "glob_to_regex translates a trailing double-star directory glob" {
  result="$(glob_to_regex 'docs/**')"
  [ "$result" = 'docs/.*' ]
}

@test "glob_to_regex translates a leading **/ into an optional path prefix" {
  result="$(glob_to_regex '**/*.md')"
  [ "$result" = '(.*/)?[^/]*\.md' ]
}

@test "glob_to_regex translates single star to a single path-segment wildcard" {
  result="$(glob_to_regex '*.test.*')"
  [ "$result" = '[^/]*\.test\.[^/]*' ]
}

@test "glob_to_regex escapes regex metacharacters in literal segments" {
  result="$(glob_to_regex 'package.json')"
  [ "$result" = 'package\.json' ]
}

@test "match_glob: docs/** matches nested docs files" {
  run match_glob "docs/guide/setup.md" "docs/**"
  [ "$status" -eq 0 ]
}

@test "match_glob: docs/** does not match files outside docs/" {
  run match_glob "src/docs/setup.md" "docs/**"
  [ "$status" -eq 1 ]
}

@test "match_glob: **/*.md matches a top-level file with no directory" {
  run match_glob "README.md" "**/*.md"
  [ "$status" -eq 0 ]
}

@test "match_glob: **/*.md matches a deeply nested file" {
  run match_glob "docs/api/v1/reference.md" "**/*.md"
  [ "$status" -eq 0 ]
}

@test "match_glob: *.test.* does not cross a directory boundary" {
  run match_glob "src/foo.test.js" "*.test.*"
  [ "$status" -eq 1 ]
}

@test "match_glob: **/*.test.* matches nested test files" {
  run match_glob "src/api/foo.test.js" "**/*.test.*"
  [ "$status" -eq 0 ]
}

@test "match_glob: literal pattern matches only the exact path" {
  run match_glob "package.json" "package.json"
  [ "$status" -eq 0 ]
  run match_glob "sub/package.json" "package.json"
  [ "$status" -eq 1 ]
}
