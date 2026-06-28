#!/usr/bin/env bats
#
# environment-matrix-generator.bats
# =================================
# End-to-end test suite for the Environment Matrix Generator.
#
# Per the task requirements, every functional test case is exercised THROUGH the
# GitHub Actions workflow via `act`: setup_file builds a clean temp git repo with
# the project files, runs `act push --rm` ONCE (the workflow loops over all
# fixtures internally), and captures the full output to ../act-result.txt. The
# individual @tests then assert on EXACT expected values parsed from that output.
#
# The remaining tests validate workflow structure (actionlint, parsed YAML,
# referenced paths) and shell-script quality (shellcheck, bash -n).
#
# Requires: bats, act, docker, jq (python3+pyyaml for the structure test).

# ---------------------------------------------------------------------------
# Per-test fixture: resolve paths used by every test.
# ---------------------------------------------------------------------------
setup() {
  PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ACT_RESULT="$PROJECT_DIR/act-result.txt"
  ACT_EXIT="$PROJECT_DIR/.act-exit"
  WF="$PROJECT_DIR/.github/workflows/environment-matrix-generator.yml"
  FIXTURES="$PROJECT_DIR/tests/fixtures"
}

# ---------------------------------------------------------------------------
# Suite-level setup: run the whole workflow once through act and capture output.
# ---------------------------------------------------------------------------
setup_file() {
  local project_dir result exitf work
  project_dir="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  result="$project_dir/act-result.txt"
  exitf="$project_dir/.act-exit"

  command -v act >/dev/null 2>&1 || {
    echo "act is required but not installed" >&2; return 1; }
  command -v docker >/dev/null 2>&1 || {
    echo "docker is required but not installed" >&2; return 1; }

  # Build an isolated temp git repo containing just the project files.
  work="$(mktemp -d)"
  cp "$project_dir/matrix-generator.sh" "$project_dir/run-fixtures.sh" "$work/"
  cp -r "$project_dir/.github" "$project_dir/tests" "$project_dir/examples" "$work/"
  [ -f "$project_dir/.actrc" ] && cp "$project_dir/.actrc" "$work/"

  # Run act once; the workflow validates every fixture internally.
  (
    cd "$work" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "bats test"
    git add -A
    git commit -qm "fixture commit" >/dev/null
    act push --rm --pull=false
  ) >"$result" 2>&1
  echo "$?" >"$exitf"

  rm -rf "$work"
}

# ---------------------------------------------------------------------------
# Helper: assert a fixed substring is present in the captured act output.
# ---------------------------------------------------------------------------
result_contains() {
  run grep -F -- "$1" "$ACT_RESULT"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Pipeline execution (through act)
# ===========================================================================

@test "act exited with code 0" {
  [ -f "$ACT_EXIT" ]
  run cat "$ACT_EXIT"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "act-result.txt artifact exists and is non-empty" {
  [ -f "$ACT_RESULT" ]
  [ -s "$ACT_RESULT" ]
}

@test "every job reported success and none failed" {
  run grep -c -F "Job succeeded" "$ACT_RESULT"
  [ "$status" -eq 0 ]
  # validate (1) + build matrix (2 combinations) = 3 jobs
  [ "$output" -ge 3 ]
  run grep -F "Job failed" "$ACT_RESULT"
  [ "$status" -ne 0 ]
}

@test "fixture runner reports overall pass for all 6 fixtures" {
  result_contains "FIXTURES TOTAL=6 PASSED=6 FAILED=0"
  result_contains "OVERALL=PASS"
}

# --- per-fixture exact-value assertions ------------------------------------

@test "basic: size is exactly 4 and strategy matches expected" {
  result_contains "basic SIZE=4"
  result_contains "basic RESULT=PASS"
  local expected
  expected="$(jq -S -c . "$FIXTURES/basic/expected.json")"
  result_contains "basic STRATEGY=$expected"
}

@test "exclude: size is exactly 5, fail-fast false, max-parallel 3" {
  result_contains "exclude SIZE=5"
  result_contains "exclude RESULT=PASS"
  local expected
  expected="$(jq -S -c . "$FIXTURES/exclude/expected.json")"
  result_contains "exclude STRATEGY=$expected"
  # the excluded combination must be present in the emitted matrix
  result_contains '"exclude":[{"node":"16","os":"windows-latest"}]'
}

@test "include: size is exactly 3 (augment + new combo)" {
  result_contains "include SIZE=3"
  result_contains "include RESULT=PASS"
  local expected
  expected="$(jq -S -c . "$FIXTURES/include/expected.json")"
  result_contains "include STRATEGY=$expected"
  # the augmenting include key and the brand-new combination are present
  result_contains '"coverage":true'
  result_contains '{"node":"21","os":"windows-latest"}'
}

@test "feature-flags: size is exactly 8 (2x2x2)" {
  result_contains "feature-flags SIZE=8"
  result_contains "feature-flags RESULT=PASS"
  local expected
  expected="$(jq -S -c . "$FIXTURES/feature-flags/expected.json")"
  result_contains "feature-flags STRATEGY=$expected"
}

@test "include-only: size is exactly 2 (one job per include)" {
  result_contains "include-only SIZE=2"
  result_contains "include-only RESULT=PASS"
  local expected
  expected="$(jq -S -c . "$FIXTURES/include-only/expected.json")"
  result_contains "include-only STRATEGY=$expected"
}

@test "oversize: generator fails with exit 3 and exact error message" {
  result_contains "oversize EXIT=3"
  result_contains "oversize RESULT=PASS"
  result_contains "27 combinations"
  result_contains "exceeds the maximum allowed size of 10"
}

# --- the generated matrix actually drives the downstream build job ----------

@test "validate job emits the generated matrix for the build job" {
  result_contains 'Generated matrix: {"os":["ubuntu-latest"],"node":["18","20"]}'
}

@test "build job runs once per generated combination" {
  result_contains "BUILD_COMBINATION os=ubuntu-latest node=18"
  result_contains "BUILD_COMBINATION os=ubuntu-latest node=20"
}

# ===========================================================================
# Workflow structure / static quality
# ===========================================================================

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "workflow passes actionlint cleanly" {
  command -v actionlint >/dev/null 2>&1 || skip "actionlint not installed"
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow references scripts that exist on disk" {
  run grep -F "run-fixtures.sh" "$WF"
  [ "$status" -eq 0 ]
  run grep -F "matrix-generator.sh" "$WF"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/run-fixtures.sh" ]
  [ -f "$PROJECT_DIR/matrix-generator.sh" ]
  [ -f "$PROJECT_DIR/examples/demo-config.json" ]
}

@test "workflow YAML has expected structure (triggers/jobs/needs/permissions)" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available"
  python3 -c "import yaml" 2>/dev/null || skip "pyyaml not available"
  run python3 "$BATS_TEST_DIRNAME/check_structure.py" "$WF"
  [ "$status" -eq 0 ]
  [[ "$output" == *STRUCTURE_OK* ]]
}

@test "matrix-generator.sh passes bash -n and shellcheck" {
  run bash -n "$PROJECT_DIR/matrix-generator.sh"
  [ "$status" -eq 0 ]
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
  run shellcheck "$PROJECT_DIR/matrix-generator.sh"
  [ "$status" -eq 0 ]
}

@test "run-fixtures.sh passes bash -n and shellcheck" {
  run bash -n "$PROJECT_DIR/run-fixtures.sh"
  [ "$status" -eq 0 ]
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
  run shellcheck "$PROJECT_DIR/run-fixtures.sh"
  [ "$status" -eq 0 ]
}
