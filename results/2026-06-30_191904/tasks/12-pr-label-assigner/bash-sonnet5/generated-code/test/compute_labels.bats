#!/usr/bin/env bats
#
# Unit tests for compute_labels(), which applies the loaded rules to a list
# of changed file paths and produces the final, deduplicated, sorted label
# set (via the global LABELS_RESULT array). Covers:
#   - a single matching rule
#   - multiple labels applying to one file (different categories)
#   - priority-based conflict resolution within the same category
#   - union/dedup of labels across multiple files
#   - files that match nothing contribute no labels

setup() {
  source "${BATS_TEST_DIRNAME}/../label-assigner.sh"
  TMPDIR_RULES="$(mktemp -d)"
  cat > "$TMPDIR_RULES/rules.conf" <<'EOF'
100|docs|docs/**|documentation
100|docs|**/*.md|documentation
90|api|src/api/**|api
95|owner|src/legacy/critical/**|core-team
85|owner|src/legacy/**|legacy-team
80|tests|**/*.test.*|tests
70|source|src/**|code
50|deps|package.json|dependencies
EOF
  load_rules "$TMPDIR_RULES/rules.conf"
}

teardown() {
  rm -rf "$TMPDIR_RULES"
}

@test "compute_labels assigns a single label for a simple docs match" {
  compute_labels "docs/guide.md"
  [ "${#LABELS_RESULT[@]}" -eq 1 ]
  [ "${LABELS_RESULT[0]}" = "documentation" ]
}

@test "compute_labels assigns multiple labels to one file across categories" {
  compute_labels "src/api/handler.test.js"
  # matches: src/api/** (api), **/*.test.* (tests), src/** (code)
  printf '%s\n' "${LABELS_RESULT[@]}" > "$TMPDIR_RULES/actual.txt"
  run cat "$TMPDIR_RULES/actual.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\ncode\ntests')" ]
}

@test "compute_labels resolves same-category conflicts by highest priority" {
  compute_labels "src/legacy/critical/payment.js"
  # src/legacy/critical/** (core-team, prio 95) beats src/legacy/** (legacy-team, prio 85)
  # both are in category "owner" so only one wins; src/** (code) is a different category.
  printf '%s\n' "${LABELS_RESULT[@]}" > "$TMPDIR_RULES/actual.txt"
  run cat "$TMPDIR_RULES/actual.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'code\ncore-team')" ]
  [[ "$output" != *"legacy-team"* ]]
}

@test "compute_labels unions and deduplicates labels across multiple files" {
  compute_labels "docs/guide.md" "README.md" "src/api/routes.js"
  printf '%s\n' "${LABELS_RESULT[@]}" > "$TMPDIR_RULES/actual.txt"
  run cat "$TMPDIR_RULES/actual.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'api\ncode\ndocumentation')" ]
}

@test "compute_labels produces no labels for files matching no rule" {
  compute_labels "random/other/file.txt"
  [ "${#LABELS_RESULT[@]}" -eq 0 ]
}

@test "compute_labels handles an empty file list" {
  compute_labels
  [ "${#LABELS_RESULT[@]}" -eq 0 ]
}
