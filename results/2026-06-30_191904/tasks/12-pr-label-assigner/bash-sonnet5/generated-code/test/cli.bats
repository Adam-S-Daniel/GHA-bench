#!/usr/bin/env bats
#
# Integration tests for the label-assigner.sh CLI entrypoint (main()).
# These invoke the script as a real subprocess (not sourced) to exercise
# argument parsing, output formats, and error handling end-to-end.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../label-assigner.sh"
  TMPDIR_CLI="$(mktemp -d)"
  cat > "$TMPDIR_CLI/rules.conf" <<'EOF'
100|docs|docs/**|documentation
90|api|src/api/**|api
80|tests|**/*.test.*|tests
EOF
  cat > "$TMPDIR_CLI/files.txt" <<'EOF'
docs/guide.md
src/api/handler.test.js
EOF
}

teardown() {
  rm -rf "$TMPDIR_CLI"
}

@test "CLI: prints usage and exits 0 with --help" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "CLI: exits 2 with a clear message when --rules is missing" {
  run "$SCRIPT" --changed-files "$TMPDIR_CLI/files.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--rules is required"* ]]
}

@test "CLI: exits 2 with a clear message when --changed-files is missing" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--changed-files is required"* ]]
}

@test "CLI: exits 2 on an unknown option" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/files.txt" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "CLI: exits 2 on an unknown --format value" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/files.txt" --format xml
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown format"* ]]
}

@test "CLI: exits 3 with a clear message when the rules file is missing" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/nope.conf" --changed-files "$TMPDIR_CLI/files.txt"
  [ "$status" -eq 3 ]
  [[ "$output" == *"rules file not found"* ]]
}

@test "CLI: exits 4 with a clear message when the changed-files list is missing" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/nope.txt"
  [ "$status" -eq 4 ]
  [[ "$output" == *"changed files list not found"* ]]
}

@test "CLI: exits 5 with a clear message on a malformed rules file" {
  echo "bogus-rule-line" > "$TMPDIR_CLI/bad_rules.conf"
  run "$SCRIPT" --rules "$TMPDIR_CLI/bad_rules.conf" --changed-files "$TMPDIR_CLI/files.txt"
  [ "$status" -eq 5 ]
  [[ "$output" == *"malformed rule"* ]]
}

@test "CLI: default text format prints one sorted label per line" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/files.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\ndocumentation\ntests')" ]
}

@test "CLI: --format csv prints a single comma-separated line" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/files.txt" --format csv
  [ "$status" -eq 0 ]
  [ "$output" = "api,documentation,tests" ]
}

@test "CLI: --format json prints an exact JSON array" {
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/files.txt" --format json
  [ "$status" -eq 0 ]
  [ "$output" = '["api","documentation","tests"]' ]
}

@test "CLI: an empty changed-files list yields an empty json array" {
  : > "$TMPDIR_CLI/empty.txt"
  run "$SCRIPT" --rules "$TMPDIR_CLI/rules.conf" --changed-files "$TMPDIR_CLI/empty.txt" --format json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "CLI: reads the changed-files list from stdin when given -" {
  run bash -c "printf 'docs/guide.md\n' | '$SCRIPT' --rules '$TMPDIR_CLI/rules.conf' --changed-files -"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}
