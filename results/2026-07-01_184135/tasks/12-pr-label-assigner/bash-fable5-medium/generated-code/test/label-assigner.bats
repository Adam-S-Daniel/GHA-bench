#!/usr/bin/env bats
# Unit tests for label-assigner.sh — the PR label assignment engine.
#
# TDD log: each @test below was written BEFORE the code that makes it pass
# (red/green cycles noted in comments). Fixtures live in test/fixtures/.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../label-assigner.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  TMP="$BATS_TEST_TMPDIR"
}

# --- Cycle 1: CLI contract / error handling -------------------------------

@test "fails with usage message when no arguments are given" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "fails with meaningful error when rules file does not exist" {
  run bash "$SCRIPT" --rules "$TMP/nope.rules" --files /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"rules file not found"* ]]
}

@test "fails with meaningful error when files list does not exist" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/nope.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed-files list not found"* ]]
}

# --- Cycle 2: basic matching and output ------------------------------------

@test "single matching rule prints its label" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  printf 'docs/setup.md\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "no matching rule prints nothing and exits 0" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  printf 'src/main.sh\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Cycle 3: real glob semantics ------------------------------------------
# '*' and '?' must not cross '/', '**' may; a pattern with no '/' is
# matched against the basename (gitignore-style).

@test "single star does not cross directory boundaries" {
  printf 'src/*.sh => shell\n' > "$TMP/r.rules"
  printf 'src/api/users.sh\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "double star crosses directory boundaries" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  printf 'docs/a/b/c.md\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "pattern without slash matches against the basename" {
  printf '*.test.* => tests\n' > "$TMP/r.rules"
  printf 'src/api/auth.test.js\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "tests" ]
}

@test "question mark matches exactly one non-slash character" {
  printf 'src/v?.sh => versioned\n' > "$TMP/r.rules"
  printf 'src/v1.sh\nsrc/v12.sh\nsrc/v.sh\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "versioned" ]
}

@test "regex metacharacters in patterns are treated literally" {
  printf 'src/a+b.sh => plus\n' > "$TMP/r.rules"
  printf 'src/aab.sh\nsrc/a+b.sh\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "plus" ]
}

@test "reads changed files from stdin when files arg is '-'" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  run bash -c "printf 'docs/a.md\n' | bash '$SCRIPT' --rules '$TMP/r.rules' --files -"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

# --- Cycle 4: multi-label rules, dedup, priority conflicts, bad rules -------

@test "basic fixture: multiple rules, multiple labels, dedup, sorted output" {
  run bash "$SCRIPT" --rules "$FIXTURES/basic.rules" --files "$FIXTURES/basic-files.txt"
  [ "$status" -eq 0 ]
  # docs/guide/setup.md -> documentation; src/api/* -> api, backend (x2,
  # deduped); auth.test.js -> tests; README.md -> nothing.
  [ "$output" = "api
backend
documentation
tests" ]
}

@test "exclusive rule wins conflicts: lower-priority rules are skipped" {
  run bash "$SCRIPT" --rules "$FIXTURES/priority.rules" --files "$FIXTURES/priority-files.txt"
  [ "$status" -eq 0 ]
  # vendor/docs/readme.md matches '! vendor/**' -> only 'vendored'
  # (docs/** and ** never evaluated for it); docs/intro.md -> documentation
  # + touched.
  [ "$output" = "documentation
touched
vendored" ]
}

@test "same file collects labels from every non-exclusive matching rule" {
  printf 'docs/** => documentation\n**/*.md => markdown\n' > "$TMP/r.rules"
  printf 'docs/a.md\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation
markdown" ]
}

@test "comments and blank lines in rules file are ignored" {
  printf '# heading\n\ndocs/** => documentation  # trailing comment\n' > "$TMP/r.rules"
  printf 'docs/a.md\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "malformed rule line fails with line-numbered error" {
  printf 'docs/** => documentation\nthis is not a rule\n' > "$TMP/r.rules"
  printf 'docs/a.md\n' > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed rule at"*":2"* ]]
}

@test "empty changed-files list yields empty label set and exit 0" {
  printf 'docs/** => documentation\n' > "$TMP/r.rules"
  : > "$TMP/f.txt"
  run bash "$SCRIPT" --rules "$TMP/r.rules" --files "$TMP/f.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
