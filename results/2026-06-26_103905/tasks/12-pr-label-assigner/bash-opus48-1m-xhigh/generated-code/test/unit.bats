#!/usr/bin/env bats
#
# Unit tests for pr-label-assigner.sh (TDD red/green/refactor).
#
# These tests exercise the script's logic directly. The end-to-end pipeline
# tests that run everything through `act` live in test/workflow.bats.

setup() {
    # Absolute path to the script under test.
    SCRIPT="$BATS_TEST_DIRNAME/../pr-label-assigner.sh"
    # A per-test scratch directory for fixtures (configs + file lists).
    TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP"
}

@test "prints usage and exits 0 with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "errors when no --config is provided" {
    run "$SCRIPT" --files /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"config"* ]]
}

@test "errors when the config file does not exist" {
    run "$SCRIPT" --config "$TMP/nope.config" --files /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "errors on an unknown option" {
    run "$SCRIPT" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# --- core glob matching ------------------------------------------------------

@test "'**' matches any depth under a directory" {
    printf 'docs/** -> documentation\n' >"$TMP/c"
    printf 'docs/guide/intro.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "'*' does not cross a directory separator" {
    printf 'src/* -> shallow\n' >"$TMP/c"
    # src/app.js is one level deep (matches); src/api/app.js is two (no match).
    printf 'src/app.js\nsrc/api/app.js\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "shallow" ]
}

@test "a pattern with no slash matches the basename at any depth" {
    printf '*.test.* -> tests\n' >"$TMP/c"
    printf 'src/components/button.test.tsx\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "tests" ]
}

@test "no matching rule yields an empty label set and exit 0" {
    printf 'docs/** -> documentation\n' >"$TMP/c"
    printf 'src/main.go\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# --- multiple labels, dedup --------------------------------------------------

@test "a single rule can assign multiple comma-separated labels" {
    printf 'src/api/** -> api,backend\n' >"$TMP/c"
    printf 'src/api/users.js\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "api"$'\n'"backend" ]
}

@test "a label assigned by several files appears only once" {
    printf 'docs/** -> documentation\n' >"$TMP/c"
    printf 'docs/a.md\ndocs/b.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "one file can collect labels from several matching rules" {
    printf 'src/api/** -> api\n*.js -> javascript\n' >"$TMP/c"
    printf 'src/api/users.js\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "api"$'\n'"javascript" ]
}

# --- priority ordering -------------------------------------------------------

@test "labels are ordered by descending priority (third '->' field)" {
    cat >"$TMP/c" <<'EOF'
src/api/** -> api -> 100
docs/**     -> documentation -> 10
*.js        -> javascript -> 50
EOF
    printf 'src/api/users.js\ndocs/readme.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "api"$'\n'"javascript"$'\n'"documentation" ]
}

@test "equal-priority labels fall back to alphabetical order" {
    cat >"$TMP/c" <<'EOF'
*.go -> zebra -> 5
*.go -> alpha -> 5
EOF
    printf 'main.go\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "alpha"$'\n'"zebra" ]
}

@test "when a label is set by several rules the highest priority wins" {
    cat >"$TMP/c" <<'EOF'
*.js   -> shared -> 1
src/** -> shared -> 99
*.js   -> other  -> 50
EOF
    printf 'src/app.js\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    # shared reaches priority 99 (> other's 50) so it sorts first.
    [ "$output" = "shared"$'\n'"other" ]
}

@test "a non-integer priority is rejected" {
    printf 'docs/** -> documentation -> high\n' >"$TMP/c"
    printf 'docs/a.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -ne 0 ]
    [[ "$output" == *"priority"* ]]
}

# --- input sources & config hygiene -----------------------------------------

@test "reads changed paths from stdin when --files is omitted" {
    printf 'docs/** -> documentation\n' >"$TMP/c"
    run "$SCRIPT" --config "$TMP/c" <<<"docs/intro.md"
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "comments and blank lines in the config are ignored" {
    cat >"$TMP/c" <<'EOF'
# this is a comment

docs/** -> documentation

# trailing comment
EOF
    printf 'docs/a.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "a config line missing '->' is rejected" {
    printf 'docs/** documentation\n' >"$TMP/c"
    printf 'docs/a.md\n' >"$TMP/f"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/f"
    [ "$status" -ne 0 ]
    [[ "$output" == *"->"* ]]
}

@test "a missing --files list is reported clearly" {
    printf 'docs/** -> documentation\n' >"$TMP/c"
    run "$SCRIPT" --config "$TMP/c" --files "$TMP/missing.txt"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
