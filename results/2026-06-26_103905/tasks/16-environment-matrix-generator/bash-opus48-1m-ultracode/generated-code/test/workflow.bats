#!/usr/bin/env bats
#
# End-to-end acceptance tests: EVERY test case is exercised through the GitHub
# Actions workflow via `act` — the script is never invoked directly here.
#
# Design note on "one act run for all cases":
#   The instructions ask for each test case to run through `act push` while also
#   capping the number of `act push` invocations. We reconcile this by letting
#   the workflow's own strategy.matrix run one leg per fixture: a single
#   `act push` therefore executes every fixture as an independent job, and the
#   harness asserts exact expected values for each from the captured output.
#   All output is saved (clearly delimited) to act-result.txt.

setup_file() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
  export ACT_RESULT="$PROJECT_ROOT/act-result.txt"
  export ACT_CODE_FILE="$PROJECT_ROOT/.act-exit-code"

  # Allow re-running the (fast) assertions against an existing act-result.txt
  # without paying for another container run: REUSE_ACT=1 bats test/workflow.bats
  if [ "${REUSE_ACT:-0}" = "1" ] && [ -f "$ACT_RESULT" ]; then
    export ACT_EXIT_CODE="$(cat "$ACT_CODE_FILE" 2>/dev/null || echo 99)"
    return 0
  fi

  # Build an isolated temp git repo containing only the files act needs.
  local tmp
  tmp="$(mktemp -d)"
  cp "$PROJECT_ROOT/generate-matrix.sh" "$tmp/"
  [ -f "$PROJECT_ROOT/.actrc" ] && cp "$PROJECT_ROOT/.actrc" "$tmp/"
  mkdir -p "$tmp/fixtures" "$tmp/.github/workflows"
  cp "$PROJECT_ROOT"/fixtures/*.json "$tmp/fixtures/"
  cp "$PROJECT_ROOT/.github/workflows/environment-matrix-generator.yml" "$tmp/.github/workflows/"

  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -qm "environment matrix generator under test"
  )

  # Single act run; capture stdout+stderr and the exit code. The `|| code=$?`
  # guard is essential: bats aborts setup_file on the first failing command, so
  # we must not let a non-zero act exit propagate before we save the output.
  # --pull=false: the mapped runner image (act-ubuntu-pwsh:latest, from .actrc)
  # is a local-only image; without this act tries to pull it and fails auth.
  local out code
  out="$(cd "$tmp" && act push --rm --pull=false 2>&1)" && code=0 || code=$?

  {
    echo "=================================================================="
    echo "== act push --rm  (all fixtures via strategy.matrix, one run)    =="
    echo "== exit code: $code"
    echo "=================================================================="
    printf '%s\n' "$out"
  } > "$ACT_RESULT"
  echo "$code" > "$ACT_CODE_FILE"
  export ACT_EXIT_CODE="$code"

  rm -rf "$tmp"
}

# Strip ANSI escapes and the leading "[Workflow/job] | " prefix act adds.
clean() { sed -E 's/\x1b\[[0-9;]*m//g' "$ACT_RESULT"; }

# Extract the compact matrix JSON a fixture printed (MATRIX_JSON line).
matrix_json() {
  local fx="$1" line
  line="$(clean | grep -F "MATRIX_JSON fixture=${fx} " | head -1)"
  printf '%s' "${line#*MATRIX_JSON fixture=${fx} }"
}

@test "act exited with code 0" {
  echo "act exit code: ${ACT_EXIT_CODE}"
  [ "$ACT_EXIT_CODE" -eq 0 ]
}

@test "act-result.txt artifact was written" {
  [ -f "$ACT_RESULT" ]
  [ -s "$ACT_RESULT" ]
}

@test "every job reports 'Job succeeded' and none failed" {
  local succeeded failed
  succeeded="$(clean | grep -c 'Job succeeded' || true)"
  failed="$(clean | grep -c 'Job failed' || true)"
  echo "Job succeeded count: $succeeded ; Job failed count: $failed"
  # 5 generate legs + validate-limit + summary = 7 jobs.
  [ "$succeeded" -eq 7 ]
  [ "$failed" -eq 0 ]
}

@test "basic fixture: 4 combinations, fail-fast true, no max-parallel" {
  clean | grep -qF "MATRIX_RESULT fixture=basic size=4 fail-fast=true max-parallel=none"
}

@test "exclude fixture: 5 combinations, fail-fast false, max-parallel 3" {
  clean | grep -qF "MATRIX_RESULT fixture=exclude size=5 fail-fast=false max-parallel=3"
}

@test "limit fixture: 6 combinations within max-size, max-parallel 2" {
  clean | grep -qF "MATRIX_RESULT fixture=limit size=6 fail-fast=true max-parallel=2"
}

@test "include-only fixture: 2 combinations, fail-fast true" {
  clean | grep -qF "MATRIX_RESULT fixture=include-only size=2 fail-fast=true max-parallel=none"
}

@test "include fixture: 6 combinations with exact GitHub Actions merge result" {
  clean | grep -qF "MATRIX_RESULT fixture=include size=6 fail-fast=true max-parallel=none"
  local json
  json="$(matrix_json include)"
  echo "include matrix: $json"
  echo "$json" | jq -e 'length == 6'
  echo "$json" | jq -e 'any(.[]; .fruit=="apple" and .animal=="cat" and .color=="pink" and .shape=="circle")'
  echo "$json" | jq -e 'any(.[]; .fruit=="apple" and .animal=="dog" and .color=="green" and .shape=="circle")'
  echo "$json" | jq -e 'any(.[]; .fruit=="pear"  and .animal=="cat" and .color=="pink")'
  echo "$json" | jq -e 'any(.[]; .fruit=="pear"  and .animal=="dog" and .color=="green")'
  echo "$json" | jq -e 'any(.[]; .fruit=="banana" and (has("animal")|not))'
  echo "$json" | jq -e 'any(.[]; .fruit=="banana" and .animal=="cat")'
}

@test "oversize fixture: rejected with exit code 2 and clear message" {
  clean | grep -qF "OVERSIZE_EXIT=2"
  clean | grep -qF "matrix size 16 exceeds maximum 10"
  clean | grep -qF "OVERSIZE_OK fixture=oversize size=16 max-size=10"
}

@test "summary job ran after its dependencies and reported success" {
  clean | grep -qF "ALL_MATRIX_CHECKS_PASSED=true"
}
