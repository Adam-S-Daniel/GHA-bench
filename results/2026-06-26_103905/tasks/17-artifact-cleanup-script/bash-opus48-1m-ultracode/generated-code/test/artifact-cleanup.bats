#!/usr/bin/env bats
#
# Test suite for the Artifact Cleanup Script (Task 17).
#
# DESIGN NOTE — "all tests through act":
#   The benchmark requires that every functional test case execute through the
#   GitHub Actions pipeline via `act`, while also capping the number of `act
#   push` invocations (≤3, because each run is 30-90s). A naive "one act run per
#   test case" design is infeasible under that cap. The resolution used here:
#     * The workflow processes EVERY fixture/test case in a SINGLE `act push`
#       run (one matrix-free loop job + a dependent report job).
#     * `setup_file` runs `act push --rm` exactly ONCE, captures the full output
#       to `act-result.txt`, and every functional @test asserts on EXACT VALUES
#       parsed out of that shared output.
#   This keeps each test case flowing through the real pipeline while respecting
#   the act-run budget.
#
# The suite also contains workflow-structure tests (file existence, script
# references, trigger/job structure, actionlint) which need no container.

# Resolve project root (parent of this test/ directory).
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${PROJECT_ROOT}/artifact-cleanup.sh"
WORKFLOW="${PROJECT_ROOT}/.github/workflows/artifact-cleanup-script.yml"
# Required artifact: the captured act output, written to the current working
# directory (the project root from which `bats` is invoked).
ACT_RESULT_FILE="${PROJECT_ROOT}/act-result.txt"

# --------------------------------------------------------------------------
# setup_file: run the whole pipeline through act EXACTLY ONCE.
#
#   * Build a throwaway git repo containing the project files + every fixture.
#   * Run `act push --rm` a single time (it processes all fixture/test cases).
#   * Capture the full output (plus the act exit code) to act-result.txt.
#
# Every act-driven @test below then asserts on EXACT VALUES grepped out of that
# shared capture, so all test cases flow through the real pipeline while the
# number of `act push` invocations stays at one.
# --------------------------------------------------------------------------
setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT
  local result="${PROJECT_ROOT}/act-result.txt"
  : >"$result"   # fresh capture each run

  if ! command -v act >/dev/null 2>&1; then
    echo "=== ACT NOT INSTALLED — cannot run pipeline ===" >>"$result"
    echo "=== ACT EXIT CODE: 127 ===" >>"$result"
    export ACT_EXIT_CODE=127
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  export ACT_TMPDIR="$tmp"

  # Copy only what the workflow needs into the isolated repo.
  cp -a "${PROJECT_ROOT}/artifact-cleanup.sh" "$tmp/"
  cp -a "${PROJECT_ROOT}/fixtures" "$tmp/"
  mkdir -p "$tmp/.github/workflows"
  cp -a "${PROJECT_ROOT}/.github/workflows/artifact-cleanup-script.yml" "$tmp/.github/workflows/"
  # Reuse the project's .actrc (maps ubuntu-latest -> the local act image).
  [ -f "${PROJECT_ROOT}/.actrc" ] && cp -a "${PROJECT_ROOT}/.actrc" "$tmp/"

  {
    echo "############################################################"
    echo "# ACT RUN — .github/workflows/artifact-cleanup-script.yml"
    echo "# event: push  (single invocation covering all fixture cases)"
    echo "# isolated repo: ${tmp}"
    echo "############################################################"
    echo ""
  } >>"$result"

  local ec
  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "bats-harness"
    git add -A
    git commit -qm "artifact cleanup pipeline test fixtures"
    act push --rm --pull=false
  ) >>"$result" 2>&1
  ec=$?

  {
    echo ""
    echo "=== ACT EXIT CODE: ${ec} ==="
  } >>"$result"
  export ACT_EXIT_CODE="$ec"
}

teardown_file() {
  [ -n "${ACT_TMPDIR:-}" ] && rm -rf "${ACT_TMPDIR}"
}

# --------------------------------------------------------------------------
# Workflow-structure tests (fast; no container required)
# --------------------------------------------------------------------------

@test "script file exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "script passes bash -n syntax validation" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script passes shellcheck" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow passes actionlint with exit code 0" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares the required trigger events" {
  grep -Eq '^[[:space:]]*push:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*pull_request:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*schedule:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*workflow_dispatch:' "$WORKFLOW"
}

@test "workflow declares permissions" {
  grep -Eq '^[[:space:]]*permissions:' "$WORKFLOW"
}

@test "workflow defines two jobs with a dependency (needs)" {
  grep -Eq '^[[:space:]]*cleanup:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*report:' "$WORKFLOW"
  grep -Eq 'needs:[[:space:]]*cleanup' "$WORKFLOW"
}

@test "workflow references the cleanup script by its real path" {
  grep -q 'artifact-cleanup.sh' "$WORKFLOW"
  # The referenced script path must actually exist.
  [ -f "$SCRIPT" ]
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'actions/checkout@v4' "$WORKFLOW"
}

@test "all fixture files referenced by the workflow exist" {
  for f in case1-age case2-keep-latest case3-size case4-combined; do
    [ -f "${PROJECT_ROOT}/fixtures/${f}.txt" ]
  done
}

# --------------------------------------------------------------------------
# Pipeline tests — every assertion below is on EXACT VALUES from the single
# `act push` capture produced in setup_file. These are the "all tests through
# act" cases required by the task.
# --------------------------------------------------------------------------

@test "act-result.txt artifact exists and is non-empty" {
  [ -s "$ACT_RESULT_FILE" ]
}

@test "act push exited with code 0" {
  grep -qF "=== ACT EXIT CODE: 0 ===" "$ACT_RESULT_FILE"
}

@test "every job reports 'Job succeeded' (both cleanup and report)" {
  run grep -c "Job succeeded" "$ACT_RESULT_FILE"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "act output contains a clearly delimited section for every case" {
  for c in case1-age case2-keep-latest case3-size case4-combined; do
    grep -qF "===== CASE: ${c} =====" "$ACT_RESULT_FILE"
  done
}

@test "plans execute in dry-run mode" {
  grep -qF "Artifact Cleanup Plan (DRY RUN)" "$ACT_RESULT_FILE"
}

@test "case1 (max-age): exact plan — delete 2, reclaim 15000000, retain 2" {
  grep -qF "RESULT case=case1-age.txt total=4 retained=2 deleted=2 reclaimed_bytes=15000000 retained_bytes=5000000" "$ACT_RESULT_FILE"
  grep -qF "OK: case1-age matches expected (deleted=2 reclaimed_bytes=15000000 retained=2)" "$ACT_RESULT_FILE"
}

@test "case2 (keep-latest): exact plan — delete 2, reclaim 2000000, retain 4" {
  grep -qF "RESULT case=case2-keep-latest.txt total=6 retained=4 deleted=2 reclaimed_bytes=2000000 retained_bytes=6000000" "$ACT_RESULT_FILE"
  grep -qF "OK: case2-keep-latest matches expected (deleted=2 reclaimed_bytes=2000000 retained=4)" "$ACT_RESULT_FILE"
}

@test "case3 (max-total-size): exact plan — delete 1, reclaim 6000000, retain 2" {
  grep -qF "RESULT case=case3-size.txt total=3 retained=2 deleted=1 reclaimed_bytes=6000000 retained_bytes=9000000" "$ACT_RESULT_FILE"
  grep -qF "OK: case3-size matches expected (deleted=1 reclaimed_bytes=6000000 retained=2)" "$ACT_RESULT_FILE"
}

@test "case4 (combined policies): exact plan — delete 2, reclaim 7000000, retain 3" {
  grep -qF "RESULT case=case4-combined.txt total=5 retained=3 deleted=2 reclaimed_bytes=7000000 retained_bytes=5500000" "$ACT_RESULT_FILE"
  grep -qF "OK: case4-combined matches expected (deleted=2 reclaimed_bytes=7000000 retained=3)" "$ACT_RESULT_FILE"
}

@test "report job emits the exact aggregate FINAL_REPORT line" {
  grep -qF "FINAL_REPORT total_cases=4 total_deleted=7 total_reclaimed_bytes=30000000 total_retained=11" "$ACT_RESULT_FILE"
  grep -qF "Aggregate totals match expected known-good values." "$ACT_RESULT_FILE"
}
