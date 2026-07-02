#!/usr/bin/env bats
#
# Test suite for the Artifact Cleanup Script (Task 17).
#
# Design note -- "every test case runs through the pipeline":
#   The task requires every functional test case to execute through the real
#   GitHub Actions workflow via `act`, while also capping `act push` to at
#   most 3 invocations (each run costs 30-90s of container startup). One
#   `act push` per fixture would blow that budget, so instead the workflow
#   itself processes every fixture in a single job run (see
#   .github/workflows/artifact-cleanup-script.yml), and this suite runs
#   `act push --rm` exactly ONCE in setup_file, capturing the full output to
#   act-result.txt. Every functional @test below then asserts on EXACT
#   values parsed out of that shared capture -- so all cases still flow
#   through the real pipeline, at the cost of a single container run.
#
#   The script's own logic was driven out with direct, fast red/green bats
#   cycles during development (not part of this final suite, per the task's
#   "do not test your script directly" instruction) -- see the fixture
#   header comments for the hand-derived expected values that both that
#   development process and this suite's assertions are built from.
#
# Tests that don't need the container (file existence, syntax, lint,
# actionlint, workflow structure) run directly and instantly.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${PROJECT_ROOT}/artifact-cleanup.sh"
WORKFLOW="${PROJECT_ROOT}/.github/workflows/artifact-cleanup-script.yml"
ACT_RESULT_FILE="${PROJECT_ROOT}/act-result.txt"

# ---------------------------------------------------------------------------
# setup_file: run the whole pipeline through act EXACTLY ONCE.
# ---------------------------------------------------------------------------
setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT
  local result="${PROJECT_ROOT}/act-result.txt"
  : >"$result"

  if ! command -v act >/dev/null 2>&1; then
    {
      echo "=== ACT NOT INSTALLED -- cannot run pipeline ==="
      echo "=== ACT EXIT CODE: 127 ==="
    } >>"$result"
    export ACT_EXIT_CODE=127
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  export ACT_TMPDIR="$tmp"

  # Isolated repo containing only what the workflow needs.
  cp -a "${PROJECT_ROOT}/artifact-cleanup.sh" "$tmp/"
  cp -a "${PROJECT_ROOT}/fixtures" "$tmp/"
  mkdir -p "$tmp/.github/workflows"
  cp -a "${PROJECT_ROOT}/.github/workflows/artifact-cleanup-script.yml" "$tmp/.github/workflows/"
  if [ -f "${PROJECT_ROOT}/.actrc" ]; then
    cp -a "${PROJECT_ROOT}/.actrc" "$tmp/"
  fi

  {
    echo "############################################################"
    echo "# ACT RUN -- .github/workflows/artifact-cleanup-script.yml"
    echo "# event: push (single invocation covering every fixture case)"
    echo "# isolated repo: ${tmp}"
    echo "############################################################"
    echo ""
  } >>"$result"

  local ec
  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "bats@example.com"
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

# ---------------------------------------------------------------------------
# Fast structural tests -- no container needed.
# ---------------------------------------------------------------------------

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
  [ -z "$output" ]
}

@test "workflow declares the required trigger events" {
  grep -Eq '^[[:space:]]*push:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*pull_request:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*schedule:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*workflow_dispatch:' "$WORKFLOW"
}

@test "workflow declares top-level permissions" {
  grep -Eq '^permissions:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*contents: read' "$WORKFLOW"
}

@test "workflow defines the cleanup and report jobs with a needs dependency" {
  grep -Eq '^[[:space:]]*cleanup:' "$WORKFLOW"
  grep -Eq '^[[:space:]]*report:' "$WORKFLOW"
  grep -Eq 'needs:[[:space:]]*cleanup' "$WORKFLOW"
}

@test "workflow uses actions/checkout@v4" {
  grep -q 'actions/checkout@v4' "$WORKFLOW"
}

@test "workflow references the cleanup script by a real, existing path" {
  grep -q 'artifact-cleanup.sh' "$WORKFLOW"
  [ -f "$SCRIPT" ]
}

@test "every fixture referenced by the workflow exists on disk" {
  for f in case1-max-age case2-keep-latest case3-max-total-bytes case4-combined case5-all-retained case6-dry-run-vs-execute; do
    grep -q "$f" "$WORKFLOW"
    [ -f "${PROJECT_ROOT}/fixtures/${f}.csv" ]
  done
}

# ---------------------------------------------------------------------------
# Pipeline tests -- every assertion is on EXACT VALUES parsed from the single
# `act push` capture produced in setup_file.
# ---------------------------------------------------------------------------

@test "act-result.txt artifact exists and is non-empty" {
  [ -s "$ACT_RESULT_FILE" ]
}

@test "act push exited with code 0" {
  grep -qF "=== ACT EXIT CODE: 0 ===" "$ACT_RESULT_FILE"
}

@test "both jobs report 'Job succeeded'" {
  run grep -c "Job succeeded" "$ACT_RESULT_FILE"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "act output contains a clearly delimited section for every fixture case" {
  for c in case1-max-age case2-keep-latest case3-max-total-bytes case4-combined case5-all-retained; do
    grep -qF "===== CASE: ${c} =====" "$ACT_RESULT_FILE"
  done
}

@test "case1 (max-age): exact plan -- total=4 retained=2 deleted=2 reclaimed_bytes=5000000" {
  grep -qF "OK: case1-max-age matches expected (total=4 retained=2 deleted=2 reclaimed_bytes=5000000)" "$ACT_RESULT_FILE"
}

@test "case2 (keep-latest): exact plan -- total=8 retained=4 deleted=4 reclaimed_bytes=7000000" {
  grep -qF "OK: case2-keep-latest matches expected (total=8 retained=4 deleted=4 reclaimed_bytes=7000000)" "$ACT_RESULT_FILE"
}

@test "case3 (max-total-bytes): exact plan -- total=3 retained=2 deleted=1 reclaimed_bytes=6000000" {
  grep -qF "OK: case3-max-total-bytes matches expected (total=3 retained=2 deleted=1 reclaimed_bytes=6000000)" "$ACT_RESULT_FILE"
}

@test "case4 (combined policies): exact plan -- total=4 retained=1 deleted=3 reclaimed_bytes=7000000" {
  grep -qF "OK: case4-combined matches expected (total=4 retained=1 deleted=3 reclaimed_bytes=7000000)" "$ACT_RESULT_FILE"
}

@test "case5 (all retained): exact plan -- total=2 retained=2 deleted=0 reclaimed_bytes=0" {
  grep -qF "OK: case5-all-retained matches expected (total=2 retained=2 deleted=0 reclaimed_bytes=0)" "$ACT_RESULT_FILE"
}

@test "dry-run leaves the state file untouched, execute mutates it, and a second execute is idempotent" {
  grep -qF "OK: dry-run left the file untouched; execute mutated it and was idempotent on rerun." "$ACT_RESULT_FILE"
}

@test "report job emits the exact aggregate FINAL_REPORT line" {
  grep -qF "FINAL_REPORT total_cases=5 total_artifacts=21 total_retained=11 total_deleted=10 total_reclaimed_bytes=25000000 total_retained_bytes=26500000" "$ACT_RESULT_FILE"
  grep -qF "Aggregate totals match known-good values; dry-run/execute semantics verified." "$ACT_RESULT_FILE"
}
