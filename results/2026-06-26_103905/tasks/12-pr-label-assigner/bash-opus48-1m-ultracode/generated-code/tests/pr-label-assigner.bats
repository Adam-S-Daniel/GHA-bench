#!/usr/bin/env bats
#
# Unit / TDD test suite for pr-label-assigner.sh
#
# These tests drive the development of the script using the red/green/refactor
# cycle: each test was written BEFORE the corresponding feature existed, watched
# fail, then made to pass with the minimum code.
#
# The script is exercised through `bash <script>` (no exec-bit dependency) and
# bats' `run` helper, which captures `$status` and `$output`.

setup() {
  # Absolute path to the script under test, regardless of where bats is invoked.
  SCRIPT="${BATS_TEST_DIRNAME}/../pr-label-assigner.sh"
  # A per-test scratch directory for fixtures we create on the fly.
  TMP="${BATS_TEST_TMPDIR}"
  RULES="${TMP}/rules.conf"
  FILES="${TMP}/files.txt"
}

# Helper: write a rules config from stdin into $RULES.
make_rules() { cat > "$RULES"; }
# Helper: write a changed-files list from stdin into $FILES.
make_files() { cat > "$FILES"; }

# ---------------------------------------------------------------------------
# Cycle 1: usage / argument handling
# ---------------------------------------------------------------------------

@test "exits with usage error (code 2) when no rules file is given" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2: file-level error handling
# ---------------------------------------------------------------------------

@test "exits 2 with a meaningful error when the rules file does not exist" {
  run bash "$SCRIPT" --rules "${TMP}/nope.conf" --files "$FILES"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rules file"* ]]
  [[ "$output" == *"nope.conf"* ]]
}

@test "exits 2 when the --files list does not exist" {
  make_rules <<< 'docs/** | documentation | 10'
  run bash "$SCRIPT" --rules "$RULES" --files "${TMP}/missing.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"files list"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 3: core glob matching -> labels
# ---------------------------------------------------------------------------

@test "a single directory glob (docs/**) assigns its label" {
  make_rules <<< 'docs/** | documentation | 10'
  make_files <<EOF
docs/index.md
docs/guide/setup.md
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "files not matching any rule produce no labels" {
  make_rules <<< 'docs/** | documentation | 10'
  make_files <<< 'src/app.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "'*' does not cross a path separator but '**' does" {
  # src/* should match a direct child only; src/** matches any depth.
  make_rules <<EOF
src/*  | shallow | 10
src/** | deep    | 5
EOF
  make_files <<< 'src/api/users.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # Only the deep (src/**) rule matches a nested file.
  [ "$output" = "deep" ]
}

@test "a single rule can assign multiple comma-separated labels" {
  make_rules <<< 'src/api/** | api,backend | 10'
  make_files <<< 'src/api/users.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # Same priority -> alphabetical ordering.
  printf '%s\n' "$output" | grep -qx 'api'
  printf '%s\n' "$output" | grep -qx 'backend'
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "labels from multiple matching rules are unioned and de-duplicated" {
  make_rules <<EOF
src/api/** | api          | 30
src/**     | source       | 5
EOF
  make_files <<< 'src/api/users.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # Higher priority first.
  [ "$(printf '%s' "$output" | head -1)" = "api" ]
  printf '%s\n' "$output" | grep -qx 'source'
}

@test "the same label from two rules appears only once" {
  make_rules <<EOF
*.spec.* | tests | 40
*.test.* | tests | 40
EOF
  make_files <<EOF
a.test.js
b.spec.js
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  [ "$output" = "tests" ]
}

# ---------------------------------------------------------------------------
# Cycle 4: priority ordering, matchBase, formats, config robustness
# ---------------------------------------------------------------------------

@test "labels are emitted in priority order (highest first), ties alphabetical" {
  make_rules <<EOF
*.test.*   | tests         | 40
src/api/** | api,backend   | 30
package.json | dependencies | 25
src/ui/**  | frontend      | 20
src/**     | source        | 5
EOF
  make_files <<EOF
src/api/auth.js
src/ui/Button.tsx
package.json
auth.test.js
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # 40:tests | 30:api,backend | 25:dependencies | 20:frontend | 5:source
  expected="tests
api
backend
dependencies
frontend
source"
  [ "$output" = "$expected" ]
}

@test "a basename pattern (no slash) matches files at any depth (matchBase)" {
  make_rules <<< '*.test.* | tests | 10'
  make_files <<< 'src/components/deep/Button.test.tsx'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  [ "$output" = "tests" ]
}

@test "--format csv joins labels with commas on a single line" {
  make_rules <<EOF
src/api/** | api,backend | 30
src/**     | source      | 5
EOF
  make_files <<< 'src/api/users.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES" --format csv
  [ "$status" -eq 0 ]
  [ "$output" = "api,backend,source" ]
}

@test "comments and blank lines in the rules file are ignored" {
  make_rules <<EOF
# This is a comment
docs/** | documentation | 10   # trailing comment

   # indented comment
EOF
  make_files <<< 'docs/x.md'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "a rule with no labels is rejected with exit 3" {
  make_rules <<< 'docs/** |    | 10'
  make_files <<< 'docs/x.md'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no labels"* ]]
}

@test "a rule with a non-integer priority is rejected with exit 3" {
  make_rules <<< 'docs/** | documentation | high'
  make_files <<< 'docs/x.md'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not an integer"* ]]
}

@test "a missing priority field defaults to 0" {
  make_rules <<EOF
docs/** | documentation
src/**  | source | 5
EOF
  make_files <<EOF
docs/x.md
src/a.js
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # source (priority 5) outranks documentation (default 0)
  expected="source
documentation"
  [ "$output" = "$expected" ]
}

@test "changed paths can be supplied as positional arguments" {
  make_rules <<< 'docs/** | documentation | 10'
  run bash "$SCRIPT" --rules "$RULES" docs/a.md docs/b.md
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "changed paths can be supplied on standard input" {
  make_rules <<< 'docs/** | documentation | 10'
  run bash -c "printf 'docs/a.md\ndocs/b.md\n' | bash '$SCRIPT' --rules '$RULES'"
  [ "$status" -eq 0 ]
  [ "$output" = "documentation" ]
}

@test "--help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 5: exclusion (negation) rules — '!pattern' removes labels
# ---------------------------------------------------------------------------

@test "an exclusion rule (!pattern) removes a label from a matching file" {
  make_rules <<EOF
src/**            | source | 5
src/api/**        | api    | 30
!**/*.generated.* | api    | 0
EOF
  make_files <<< 'src/api/client.generated.js'
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # 'api' is excluded for this generated file; 'source' survives.
  [ "$output" = "source" ]
}

@test "exclusion is per-file: an unexcluded file still gets the label" {
  make_rules <<EOF
src/api/**        | api | 30
!**/*.generated.* | api | 0
EOF
  make_files <<EOF
src/api/client.generated.js
src/api/users.js
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # users.js still contributes 'api'.
  [ "$output" = "api" ]
}

@test "an exclusion rule with '*' labels suppresses all labels for the file" {
  make_rules <<EOF
docs/**       | documentation | 10
!**/vendor/** | *             | 0
EOF
  make_files <<EOF
docs/vendor/lib.md
docs/guide.md
EOF
  run bash "$SCRIPT" --rules "$RULES" --files "$FILES"
  [ "$status" -eq 0 ]
  # vendor file contributes nothing; guide.md still yields documentation.
  [ "$output" = "documentation" ]
}
