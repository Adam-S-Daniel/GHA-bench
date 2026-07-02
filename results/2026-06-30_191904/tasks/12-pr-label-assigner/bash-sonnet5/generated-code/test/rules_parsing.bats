#!/usr/bin/env bats
#
# Unit tests for load_rules(), which parses a "priority|category|pattern|label"
# rules file into parallel global arrays: RULE_PRIORITY, RULE_CATEGORY,
# RULE_PATTERN, RULE_LABEL. Comments (#) and blank lines are ignored.
# Malformed lines must fail loudly with a line-numbered error message.

setup() {
  source "${BATS_TEST_DIRNAME}/../label-assigner.sh"
  TMPDIR_RULES="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_RULES"
}

@test "load_rules parses valid rules into parallel arrays" {
  cat > "$TMPDIR_RULES/rules.conf" <<'EOF'
# comment line, should be ignored

100|docs|docs/**|documentation
80|tests|**/*.test.*|tests
EOF
  load_rules "$TMPDIR_RULES/rules.conf"

  [ "${#RULE_PRIORITY[@]}" -eq 2 ]
  [ "${RULE_PRIORITY[0]}" = "100" ]
  [ "${RULE_CATEGORY[0]}" = "docs" ]
  [ "${RULE_PATTERN[0]}" = "docs/**" ]
  [ "${RULE_LABEL[0]}" = "documentation" ]
  [ "${RULE_PRIORITY[1]}" = "80" ]
  [ "${RULE_LABEL[1]}" = "tests" ]
}

@test "load_rules resets arrays on each call (no stale state)" {
  cat > "$TMPDIR_RULES/rules_a.conf" <<'EOF'
100|docs|docs/**|documentation
EOF
  cat > "$TMPDIR_RULES/rules_b.conf" <<'EOF'
50|deps|package.json|dependencies
60|deps2|other.json|other
EOF
  load_rules "$TMPDIR_RULES/rules_a.conf"
  load_rules "$TMPDIR_RULES/rules_b.conf"

  [ "${#RULE_PRIORITY[@]}" -eq 2 ]
  [ "${RULE_LABEL[0]}" = "dependencies" ]
}

@test "load_rules errors clearly when the rules file does not exist" {
  run load_rules "$TMPDIR_RULES/does-not-exist.conf"
  [ "$status" -eq 3 ]
  [[ "$output" == *"rules file not found"* ]]
  [[ "$output" == *"does-not-exist.conf"* ]]
}

@test "load_rules errors clearly on a line with the wrong number of fields" {
  cat > "$TMPDIR_RULES/bad.conf" <<'EOF'
100|docs|docs/**
EOF
  run load_rules "$TMPDIR_RULES/bad.conf"
  [ "$status" -eq 5 ]
  [[ "$output" == *"line 1"* ]]
  [[ "$output" == *"bad.conf"* ]]
}

@test "load_rules errors clearly when priority is not an integer" {
  cat > "$TMPDIR_RULES/bad.conf" <<'EOF'
high|docs|docs/**|documentation
EOF
  run load_rules "$TMPDIR_RULES/bad.conf"
  [ "$status" -eq 5 ]
  [[ "$output" == *"priority"* ]]
  [[ "$output" == *"line 1"* ]]
}

@test "load_rules reports the correct 1-based line number for malformed lines after valid ones" {
  cat > "$TMPDIR_RULES/bad.conf" <<'EOF'
100|docs|docs/**|documentation
# a comment

not-an-int|tests|**/*.test.*|tests
EOF
  run load_rules "$TMPDIR_RULES/bad.conf"
  [ "$status" -eq 5 ]
  [[ "$output" == *"line 4"* ]]
}
