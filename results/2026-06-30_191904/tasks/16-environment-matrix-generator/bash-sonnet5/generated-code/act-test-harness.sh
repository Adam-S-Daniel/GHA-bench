#!/usr/bin/env bash
#
# act-test-harness.sh -- Runs the environment-matrix-generator workflow
# through `act` for two distinct scenarios, saves the combined output of
# both runs to act-result.txt (clearly delimited), and asserts on exact
# expected values (not just "did something print").
#
# Scenario A ("push-default"): a `push` event. The workflow's lint-and-test
# job runs the full bats suite (which exercises every fixture-driven case in
# fixtures/ -- this is how "every test case" ends up executing through the
# GitHub Actions pipeline rather than being invoked directly), then
# generate-matrix resolves fixtures/ci-example.json, then build fans out
# over the resulting 4-cell matrix.
#
# Scenario B ("workflow-dispatch-with-rules"): a `workflow_dispatch` event
# with an explicit `config_file` input, demonstrating the generator wired up
# to a parameterized trigger and exercising combined exclude+include rules
# end-to-end (fixtures/ci-example-with-rules.json, resolving to 2 cells).
#
# NOTE ON SCOPE: this repo's dedicated `matrix-generator.sh` unit tests
# (tests/matrix_generator.bats, 19 cases covering every validation/resolution
# path) all run *inside* the container via the lint-and-test job above -- not
# invoked directly by this harness -- satisfying "do not test your script
# directly, all testing goes through the pipeline." This harness additionally
# asserts on exact values from two distinct trigger scenarios above and beyond
# what bats alone proves, without exceeding the 3-`act`-invocation budget.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
FAILURES=0

: > "$RESULT_FILE"

log() { echo "[harness] $*"; }

fail() {
  echo "[harness] ASSERTION FAILED: $*" >&2
  FAILURES=$((FAILURES + 1))
}

assert_contains() {
  local haystack="$1" needle="$2" description="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$description -- expected to find: $needle"
  else
    log "PASS: $description"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$description -- did not expect to find: $needle"
  else
    log "PASS: $description"
  fi
}

# run_scenario_capturing <name> <act-args...>: sets up a fresh temp git repo
# with a copy of the project, runs `act` with the given args, appends the
# delimited output to act-result.txt, and returns the captured output via
# the global SCENARIO_OUTPUT / SCENARIO_STATUS variables.
run_scenario_capturing() {
  local name="$1"
  shift
  local tmp_dir out
  tmp_dir="$(mktemp -d)"

  cp -a "$PROJECT_ROOT/matrix-generator.sh" "$PROJECT_ROOT/lib" \
        "$PROJECT_ROOT/fixtures" "$PROJECT_ROOT/tests" \
        "$PROJECT_ROOT/.github" "$PROJECT_ROOT/.actrc" "$tmp_dir/"

  pushd "$tmp_dir" >/dev/null || exit 1
  git init -q
  git -c user.email="harness@test.local" -c user.name="harness" add -A
  git -c user.email="harness@test.local" -c user.name="harness" commit -q -m "test case: $name" >/dev/null
  out="$(act "$@" --rm 2>&1)"
  SCENARIO_STATUS=$?
  popd >/dev/null || exit 1
  rm -rf "$tmp_dir"

  SCENARIO_OUTPUT="$out"

  {
    echo "===== TEST CASE: $name ====="
    echo "command: act $* --rm"
    echo "$out"
    echo "===== END TEST CASE: $name (exit=$SCENARIO_STATUS) ====="
    echo
  } >> "$RESULT_FILE"
}

# --- Scenario A: push event, default config (fixtures/ci-example.json) ----

log "Running scenario A (push-default)..."
run_scenario_capturing "push-default" push
out="$SCENARIO_OUTPUT"

if [[ "$SCENARIO_STATUS" -ne 0 ]]; then
  fail "scenario A: act exited with status $SCENARIO_STATUS (expected 0)"
else
  log "PASS: scenario A: act exited 0"
fi

# The full bats suite (19 cases, every fixture-driven path) ran inside the
# container as part of the lint-and-test job -- assert the exact count and
# that nothing failed.
assert_contains "$out" "1..19" "scenario A: bats reports exactly 19 planned tests"
assert_contains "$out" "ok 19 exclude and include rules compose correctly" "scenario A: bats' 19th test ran and passed"
assert_not_contains "$out" "not ok" "scenario A: no bats test failed"

# generate-matrix resolved fixtures/ci-example.json to this exact strategy.
EXPECTED_STRATEGY_A='{"matrix":{"include":[{"os":"ubuntu-latest","node":"18","experimental":true},{"os":"ubuntu-latest","node":"18","experimental":false},{"os":"ubuntu-latest","node":"20","experimental":true},{"os":"ubuntu-latest","node":"20","experimental":false}]},"fail-fast":false,"max-parallel":4}'
assert_contains "$out" "Generated strategy: $EXPECTED_STRATEGY_A" "scenario A: generate-matrix produced the exact expected strategy JSON"

# build fanned out over all 4 resolved cells with the exact values.
assert_contains "$out" "Building on ubuntu-latest with node 18 (experimental=true)" "scenario A: build ran cell node=18/experimental=true"
assert_contains "$out" "Building on ubuntu-latest with node 18 (experimental=false)" "scenario A: build ran cell node=18/experimental=false"
assert_contains "$out" "Building on ubuntu-latest with node 20 (experimental=true)" "scenario A: build ran cell node=20/experimental=true"
assert_contains "$out" "Building on ubuntu-latest with node 20 (experimental=false)" "scenario A: build ran cell node=20/experimental=false"

# Every job (lint-and-test, generate-matrix, and all 4 build cells = 6 job
# runs total) must report success, and none may report failure.
job_succeeded_count=$(grep -c "Job succeeded" <<<"$out" || true)
if [[ "$job_succeeded_count" -eq 6 ]]; then
  log "PASS: scenario A: exactly 6 job runs reported 'Job succeeded' (lint-and-test + generate-matrix + 4 build cells)"
else
  fail "scenario A: expected 6 'Job succeeded' lines, found $job_succeeded_count"
fi
assert_not_contains "$out" "Job failed" "scenario A: no job reported failure"

# --- Scenario B: workflow_dispatch with an explicit config_file input -----

log "Running scenario B (workflow-dispatch-with-rules)..."
run_scenario_capturing "workflow-dispatch-with-rules" workflow_dispatch --input config_file=fixtures/ci-example-with-rules.json
out="$SCENARIO_OUTPUT"

if [[ "$SCENARIO_STATUS" -ne 0 ]]; then
  fail "scenario B: act exited with status $SCENARIO_STATUS (expected 0)"
else
  log "PASS: scenario B: act exited 0"
fi

assert_contains "$out" "1..19" "scenario B: bats reports exactly 19 planned tests"
assert_not_contains "$out" "not ok" "scenario B: no bats test failed"

# generate-matrix resolved fixtures/ci-example-with-rules.json (combined
# exclude + include rules) to this exact strategy.
EXPECTED_STRATEGY_B='{"matrix":{"include":[{"os":"ubuntu-latest","node":"18"},{"os":"ubuntu-latest","node":"22","codename":"jammy-plus"}]},"fail-fast":true}'
assert_contains "$out" "Generated strategy: $EXPECTED_STRATEGY_B" "scenario B: generate-matrix produced the exact expected strategy JSON"

assert_contains "$out" "Building on ubuntu-latest with node 18 (experimental=)" "scenario B: build ran cell node=18"
assert_contains "$out" "Building on ubuntu-latest with node 22 (experimental=)" "scenario B: build ran cell node=22/codename=jammy-plus"

job_succeeded_count=$(grep -c "Job succeeded" <<<"$out" || true)
if [[ "$job_succeeded_count" -eq 4 ]]; then
  log "PASS: scenario B: exactly 4 job runs reported 'Job succeeded' (lint-and-test + generate-matrix + 2 build cells)"
else
  fail "scenario B: expected 4 'Job succeeded' lines, found $job_succeeded_count"
fi
assert_not_contains "$out" "Job failed" "scenario B: no job reported failure"

# --- Summary ----------------------------------------------------------------

echo
if [[ "$FAILURES" -eq 0 ]]; then
  log "ALL ASSERTIONS PASSED. Full output saved to $RESULT_FILE"
  exit 0
else
  log "$FAILURES assertion(s) FAILED. See $RESULT_FILE for full act output."
  exit 1
fi
