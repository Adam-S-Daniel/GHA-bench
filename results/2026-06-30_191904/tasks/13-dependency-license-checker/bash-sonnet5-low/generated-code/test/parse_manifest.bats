#!/usr/bin/env bats
# Tests for manifest parsing (package.json / requirements.txt -> "name version" lines)

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "$DIR/lib/manifest_parser.sh"
}

@test "parse_package_json extracts dependency names and versions" {
  run parse_package_json "$DIR/test/fixtures/package.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"left-pad 1.3.0"* ]]
  [[ "$output" == *"gpl-lib 2.0.0"* ]]
  [[ "$output" == *"mystery-pkg 0.1.0"* ]]
}

@test "parse_requirements_txt extracts dependency names and versions" {
  run parse_requirements_txt "$DIR/test/fixtures/requirements.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requests 2.31.0"* ]]
  [[ "$output" == *"flask >=2.0.0"* ]]
  [[ "$output" == *"mystery-pkg 0.1.0"* ]]
}

@test "parse_manifest errors on missing file" {
  run parse_manifest "/no/such/file.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "parse_manifest dispatches based on filename" {
  run parse_manifest "$DIR/test/fixtures/package.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"left-pad 1.3.0"* ]]
}
