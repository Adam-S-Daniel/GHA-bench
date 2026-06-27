#!/usr/bin/env bats
#
# Unit tests (TDD red/green) for label-assigner.sh.
#
# These tests drive the script through its public CLI boundary:
#   label-assigner.sh --rules <rules-file> --files <files-list> [--format csv|lines]
#
# Each test builds its own throwaway rules + changed-file fixtures inside
# $BATS_TEST_TMPDIR so cases are fully isolated from one another.

setup() {
    # Absolute path to the script under test (one dir up from test/).
    SCRIPT="${BATS_TEST_DIRNAME}/../label-assigner.sh"
    RULES="${BATS_TEST_TMPDIR}/rules.conf"
    FILES="${BATS_TEST_TMPDIR}/files.txt"
}

# Helper: write a rules file from a heredoc passed on stdin.
write_rules() { cat > "$RULES"; }
# Helper: write a changed-files list from a heredoc passed on stdin.
write_files() { cat > "$FILES"; }

@test "single docs rule labels a docs file as documentation" {
    write_rules <<'EOF'
docs/** -> documentation 50
EOF
    write_files <<'EOF'
docs/intro.md
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "** crosses directories (docs/** matches a nested file)" {
    write_rules <<'EOF'
docs/** -> documentation 50
EOF
    write_files <<'EOF'
docs/guide/advanced/setup.md
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "single star does NOT cross directories" {
    # *.test.* is top-level only; a nested file must NOT match it.
    write_rules <<'EOF'
*.test.* -> tests 90
EOF
    write_files <<'EOF'
src/app/widget.test.js
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "**/*.test.* matches a nested test file" {
    write_rules <<'EOF'
**/*.test.* -> tests 90
EOF
    write_files <<'EOF'
src/app/widget.test.js
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "tests" ]
}

@test "**/ also matches a file at the repository root" {
    write_rules <<'EOF'
**/*.test.* -> tests 90
EOF
    write_files <<'EOF'
widget.test.js
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "tests" ]
}

@test "a single file can collect multiple labels from multiple rules" {
    write_rules <<'EOF'
src/api/** -> api 80
src/** -> backend 30
**/*.test.* -> tests 90
EOF
    write_files <<'EOF'
src/api/users.test.js
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    # priority DESC: tests(90), api(80), backend(30)
    [ "$output" = "tests,api,backend" ]
}

@test "labels are ordered by priority descending" {
    write_rules <<'EOF'
a/** -> low 10
b/** -> high 90
c/** -> mid 50
EOF
    write_files <<'EOF'
a/x
b/y
c/z
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "high,mid,low" ]
}

@test "equal-priority labels break ties alphabetically" {
    write_rules <<'EOF'
config/** -> zebra,apple 25
EOF
    write_files <<'EOF'
config/app.json
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    # same priority (25) -> name ascending
    [ "$output" = "apple,zebra" ]
}

@test "one rule can assign multiple comma-separated labels" {
    write_rules <<'EOF'
config/** -> config,backend 25
EOF
    write_files <<'EOF'
config/database.yml
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "backend,config" ]
}

@test "the same label from rules of different priority keeps the highest" {
    write_rules <<'EOF'
**/*.md -> documentation 50
docs/** -> documentation 70
EOF
    write_files <<'EOF'
docs/intro.md
src/api/** -> api 80
EOF
    # (second file line is just a path; it does not match the .md/docs rules)
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "labels are de-duplicated into a set" {
    write_rules <<'EOF'
docs/** -> documentation 50
**/*.md -> documentation 50
EOF
    write_files <<'EOF'
docs/a.md
docs/b.md
README.md
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "no matching rule yields an empty label set" {
    write_rules <<'EOF'
docs/** -> documentation 50
EOF
    write_files <<'EOF'
LICENSE
Makefile
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "default format prints one label per line" {
    write_rules <<'EOF'
src/api/** -> api 80
src/** -> backend 30
EOF
    write_files <<'EOF'
src/api/users.js
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "api" ]
    [ "${lines[1]}" = "backend" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "an exact-path rule matches only that exact file" {
    write_rules <<'EOF'
package.json -> dependencies 60
EOF
    write_files <<'EOF'
package.json
src/package.json
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    # nested src/package.json must NOT match the root-anchored exact rule
    [ "$output" = "dependencies" ]
}

@test "the changed-file list can be read from stdin" {
    write_rules <<'EOF'
docs/** -> documentation 50
EOF
    run bash "$SCRIPT" --rules "$RULES" --files - --format csv <<'EOF'
docs/readme.md
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "comments and blank lines in the rules file are ignored" {
    write_rules <<'EOF'
# this is a comment

docs/** -> documentation 50
   # indented comment
EOF
    write_files <<'EOF'
docs/x.md
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "missing rules file fails with a meaningful error" {
    run bash "$SCRIPT" --rules "${BATS_TEST_TMPDIR}/nope.conf" --files "$FILES" --format csv
    [ "$status" -ne 0 ]
    [[ "$output" == *"rules file not found"* ]]
}

@test "a malformed rule line (no '->') fails with the line number" {
    write_rules <<'EOF'
docs/** -> documentation 50
this line has no arrow
EOF
    write_files <<'EOF'
docs/x.md
EOF
    run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed rule"* ]]
    [[ "$output" == *"line 2"* ]]
}

@test "missing required --files argument fails" {
    write_rules <<'EOF'
docs/** -> documentation 50
EOF
    run bash "$SCRIPT" --rules "$RULES"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing required --files"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
