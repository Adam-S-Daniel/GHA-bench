#!/usr/bin/env bats
#
# Pipeline tests: every assertion here is made against the OUTPUT of the
# GitHub Actions workflow executed locally via `act`. The script is never run
# directly in this file — all testing goes through the pipeline.
#
# Structure tests (YAML shape, script references, actionlint) run cheaply on
# every invocation. The act runs are gated behind a shared, cached helper so we
# execute `act push` at most twice (well under the 3-run budget).

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
WORKFLOW="$PROJECT_ROOT/.github/workflows/environment-matrix-generator.yml"
ACT_RESULT="$PROJECT_ROOT/act-result.txt"

# run_act_case FIXTURE — set up an isolated temp git repo containing the
# project plus FIXTURE copied to fixtures/active.json, run `act push --rm`,
# append the output to act-result.txt, and echo "EXIT=<code>" then the output.
# Cached per fixture so re-querying within a run does not re-invoke act.
run_act_case() {
  local fixture="$1"
  local cache="$BATS_FILE_TMPDIR/act-${fixture}.out"
  [ -f "$cache" ] && { cat "$cache"; return 0; }

  local work; work="$(mktemp -d)"
  # Copy the project files needed to run the workflow.
  cp "$PROJECT_ROOT/matrix-gen.sh" "$work/"
  cp "$PROJECT_ROOT/.actrc" "$work/" 2>/dev/null || true
  mkdir -p "$work/.github/workflows" "$work/fixtures"
  cp "$WORKFLOW" "$work/.github/workflows/"
  cp "$PROJECT_ROOT/fixtures/$fixture" "$work/fixtures/active.json"

  # A git repo is required for actions/checkout to operate under act.
  (
    cd "$work"
    git init -q
    git config user.email t@t.t
    git config user.name t
    git add -A
    git commit -qm fixture
  )

  local out code
  # --pull=false: the act-ubuntu image is provided locally (see .actrc); without
  # this act force-pulls it from a registry and fails.
  out="$(cd "$work" && act push --rm --pull=false 2>&1)"; code=$?

  # Append clearly delimited output to the required artifact.
  {
    echo "==================== ACT CASE: $fixture ===================="
    echo "$out"
    echo "-------------------- EXIT CODE: $code --------------------"
    echo
  } >>"$ACT_RESULT"

  rm -rf "$work"
  printf 'EXIT=%s\n%s\n' "$code" "$out" >"$cache"
  cat "$cache"
}

# Fresh artifact at the start of the file's run.
setup_file() {
  : >"$ACT_RESULT"
}

# ---------------------------------------------------------------------------
# Workflow structure tests
# ---------------------------------------------------------------------------
@test "workflow file exists and references the script + fixtures" {
  [ -f "$WORKFLOW" ]
  grep -q 'matrix-gen.sh' "$WORKFLOW"
  grep -q 'fixtures/active.json' "$WORKFLOW"
  [ -f "$PROJECT_ROOT/matrix-gen.sh" ]
  [ -f "$PROJECT_ROOT/fixtures/active.json" ]
}

@test "workflow declares the expected triggers" {
  grep -q '^on:' "$WORKFLOW"
  grep -q 'push:' "$WORKFLOW"
  grep -q 'pull_request:' "$WORKFLOW"
  grep -q 'workflow_dispatch:' "$WORKFLOW"
  grep -q 'schedule:' "$WORKFLOW"
}

@test "workflow declares permissions and the generate/consume jobs" {
  grep -q 'permissions:' "$WORKFLOW"
  grep -q 'contents: read' "$WORKFLOW"
  grep -qE '^[[:space:]]+generate:' "$WORKFLOW"
  grep -qE '^[[:space:]]+consume:' "$WORKFLOW"
  grep -q 'needs: generate' "$WORKFLOW"
  grep -q 'actions/checkout@v4' "$WORKFLOW"
}

@test "actionlint passes cleanly" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Pipeline (act) tests — Case A: fixtures/sample.json
#   2 os x 2 node, minus 1 exclude, plus 1 include = 4 jobs, size <= 10.
#   Expected strategy: fail-fast=false, max-parallel=2, 2 axes.
# ---------------------------------------------------------------------------
@test "act: sample fixture runs and both jobs succeed" {
  run run_act_case sample.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXIT=0"* ]]
  # Both jobs must report success.
  succeeded="$(grep -c 'Job succeeded' <<<"$output")"
  [ "$succeeded" -ge 2 ]
}

@test "act: sample fixture emits the exact strategy JSON" {
  run run_act_case sample.json
  [ "$status" -eq 0 ]
  expected='{"fail-fast":false,"matrix":{"os":["ubuntu-latest","windows-latest"],"node":["18","20"],"exclude":[{"os":"windows-latest","node":"18"}],"include":[{"os":"macos-latest","node":"21"}]},"max-parallel":2}'
  grep -Fq "$expected" <<<"$output"
}

@test "act: sample fixture reports fail-fast=false and 2 axes" {
  run run_act_case sample.json
  [ "$status" -eq 0 ]
  grep -Fq 'FAIL_FAST=false' <<<"$output"
  grep -Fq 'AXIS_COUNT=2' <<<"$output"
  grep -Fq 'DOWNSTREAM_AXES=2' <<<"$output"
}

# ---------------------------------------------------------------------------
# Pipeline (act) tests — Case B: fixtures/simple.json
#   1 os x 3 python = 3 jobs, no size guard. fail-fast defaults to true.
# ---------------------------------------------------------------------------
@test "act: simple fixture runs and both jobs succeed" {
  run run_act_case simple.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXIT=0"* ]]
  succeeded="$(grep -c 'Job succeeded' <<<"$output")"
  [ "$succeeded" -ge 2 ]
}

@test "act: simple fixture emits the exact strategy JSON with default fail-fast" {
  run run_act_case simple.json
  [ "$status" -eq 0 ]
  expected='{"fail-fast":true,"matrix":{"os":["ubuntu-latest"],"python":["3.10","3.11","3.12"]}}'
  grep -Fq "$expected" <<<"$output"
  grep -Fq 'FAIL_FAST=true' <<<"$output"
  grep -Fq 'AXIS_COUNT=2' <<<"$output"
}

@test "act-result.txt artifact exists and is non-empty" {
  [ -s "$ACT_RESULT" ]
}
