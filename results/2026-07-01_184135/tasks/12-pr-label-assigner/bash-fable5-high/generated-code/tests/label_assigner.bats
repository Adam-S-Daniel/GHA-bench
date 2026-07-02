#!/usr/bin/env bats
# shellcheck disable=SC2154  # $status/$output/$stderr are set by bats' run
# Tests for label-assigner.sh — a PR label assigner driven by a rules file.
#
# Rules file format (one rule per line, '#' comments and blank lines ignored):
#   priority|glob-pattern|label1,label2[,...][|stop]
#
#   - priority: integer; LOWER number = HIGHER priority (evaluated first)
#   - glob-pattern: supports **, *, ? ; a pattern without '/' matches the
#     file's basename (like .gitignore), a pattern with '/' matches the
#     whole path
#   - labels: comma-separated list applied when the pattern matches
#   - stop: optional flag; when a 'stop' rule matches a file, lower-priority
#     rules are NOT evaluated for that file (conflict resolution)
#
# Output: the final label set, sorted, one label per line, on stdout.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../label-assigner.sh"
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

# Helper: write a rules file from stdin
write_rules() {
  cat > "$WORKDIR/rules.conf"
}

# Helper: write the changed-files list from stdin
write_files() {
  cat > "$WORKDIR/changed.txt"
}

run_assigner() {
  # --separate-stderr: $output is stdout (the label set), $stderr the notices
  run --separate-stderr "$SCRIPT" -r "$WORKDIR/rules.conf" -f "$WORKDIR/changed.txt"
}

@test "docs/** rule labels a docs file as documentation" {
  write_rules <<'EOF'
10|docs/**|documentation
EOF
  write_files <<'EOF'
docs/guide/intro.md
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "pattern without slash matches basename of nested files (*.test.*)" {
  write_rules <<'EOF'
10|*.test.*|tests
EOF
  write_files <<'EOF'
src/deep/nested/widget.test.js
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "tests" ]
}

@test "single * does not cross directory boundaries" {
  write_rules <<'EOF'
10|src/*.js|source
EOF
  write_files <<'EOF'
src/api/handler.js
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "a rule can apply multiple labels to one file" {
  write_rules <<'EOF'
10|src/api/**|api,backend
EOF
  write_files <<'EOF'
src/api/users.py
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\nbackend')" ]
}

@test "labels from all matching rules are aggregated and deduplicated" {
  write_rules <<'EOF'
10|docs/**|documentation
20|src/api/**|api
30|*.test.*|tests
40|**/*.md|documentation
EOF
  write_files <<'EOF'
docs/intro.md
src/api/users.py
src/api/users.test.py
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\ndocumentation\ntests')" ]
}

@test "a matching 'stop' rule suppresses lower-priority rules for that file" {
  # docs/api/readme.md matches both rules, but the docs rule has higher
  # priority (lower number) and is marked 'stop', so 'api' must NOT apply.
  write_rules <<'EOF'
10|docs/**|documentation|stop
20|**/api/**|api
EOF
  write_files <<'EOF'
docs/api/readme.md
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "priority order comes from the priority column, not line order" {
  # Same conflict as above, but the rules appear in reverse order in the
  # file. The priority column must decide which rule wins.
  write_rules <<'EOF'
20|**/api/**|api
10|docs/**|documentation|stop
EOF
  write_files <<'EOF'
docs/api/readme.md
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "a 'stop' rule only suppresses rules for files it matched" {
  write_rules <<'EOF'
10|docs/**|documentation|stop
20|**/api/**|api
EOF
  write_files <<'EOF'
docs/api/readme.md
src/api/users.py
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\ndocumentation')" ]
}

@test "comments and blank lines in the rules file are ignored" {
  write_rules <<'EOF'
# route documentation changes

10|docs/**|documentation
EOF
  write_files <<'EOF'
docs/intro.md
EOF
  run_assigner
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "changed files can be piped on stdin instead of -f" {
  write_rules <<'EOF'
10|docs/**|documentation
EOF
  run bash -c "echo docs/intro.md | '$SCRIPT' -r '$WORKDIR/rules.conf'"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "no matching rule yields empty label set, a notice, and exit 0" {
  write_rules <<'EOF'
10|docs/**|documentation
EOF
  write_files <<'EOF'
Makefile
EOF
  run --separate-stderr "$SCRIPT" -r "$WORKDIR/rules.conf" -f "$WORKDIR/changed.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ $stderr == *"no labels matched"* ]]
}

@test "missing rules file fails with a meaningful error" {
  write_files <<'EOF'
docs/intro.md
EOF
  run "$SCRIPT" -r "$WORKDIR/nope.conf" -f "$WORKDIR/changed.txt"
  [ "$status" -eq 2 ]
  [[ $output == *"rules file not found"* ]]
  [[ $output == *"nope.conf"* ]]
}

@test "missing changed-files file fails with a meaningful error" {
  write_rules <<'EOF'
10|docs/**|documentation
EOF
  run "$SCRIPT" -r "$WORKDIR/rules.conf" -f "$WORKDIR/nope.txt"
  [ "$status" -eq 2 ]
  [[ $output == *"changed-files list not found"* ]]
}

@test "malformed rule line fails with the offending line number" {
  write_rules <<'EOF'
10|docs/**|documentation
oops-not-a-rule
EOF
  write_files <<'EOF'
docs/intro.md
EOF
  run_assigner
  [ "$status" -eq 2 ]
  [[ $stderr == *"invalid rule"* ]]
  [[ $stderr == *"line 2"* ]]
}

@test "non-numeric priority is rejected" {
  write_rules <<'EOF'
high|docs/**|documentation
EOF
  write_files <<'EOF'
docs/intro.md
EOF
  run_assigner
  [ "$status" -eq 2 ]
  [[ $stderr == *"invalid rule"* ]]
}

@test "missing -r option fails with usage message" {
  write_files <<'EOF'
docs/intro.md
EOF
  run "$SCRIPT" -f "$WORKDIR/changed.txt"
  [ "$status" -eq 2 ]
  [[ $output == *"usage:"* ]]
}
