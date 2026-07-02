#!/usr/bin/env bash
#
# run_act_tests.sh — End-to-end test harness that runs EVERY test through
# the GitHub Actions pipeline via nektos/act.
#
# For each test case it:
#   1. builds a temporary git repo containing the project files plus the
#      case's fixture config installed as config.json,
#   2. runs `act push --rm` in that repo (which executes the full bats
#      unit-test suite inside the container AND exercises the generator
#      plus the dynamic-matrix consumer job),
#   3. appends the full act output to act-result.txt (clearly delimited),
#   4. asserts act exited 0, that the logs contain the EXACT expected
#      matrix JSON and the exact expected per-combination build lines,
#      and that every job reports "Job succeeded".
#
# Exit code: 0 when all cases pass, 1 otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
FAILURES=0

: > "$RESULT_FILE"

log() { printf '%s\n' "$*"; }

fail() {
  log "  ASSERT FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

pass() { log "  ASSERT OK:   $*"; }

# run_case NAME CONFIG_FIXTURE EXPECTED_STRATEGY EXPECTED_JOB_COUNT LINE...
#   NAME              — human-readable case name
#   CONFIG_FIXTURE    — fixture file installed as config.json in the repo
#   EXPECTED_STRATEGY — exact compact JSON the generator must emit
#   EXPECTED_JOB_COUNT— exact number of "Job succeeded" lines expected
#   LINE...           — exact BUILD_COMBO lines that must appear in the logs
run_case() {
  local name="$1" fixture="$2" expected_strategy="$3" expected_jobs="$4"
  shift 4
  local -a expected_lines=("$@")

  log "=== act case: $name ==="

  local tmp
  tmp="$(mktemp -d)" || { fail "could not create temp dir"; return; }

  # Assemble an isolated repo: project files + this case's config fixture.
  cp "$ROOT/matrix-gen.sh" "$tmp/"
  cp -r "$ROOT/test" "$tmp/test"
  mkdir -p "$tmp/.github/workflows"
  cp "$ROOT/.github/workflows/environment-matrix-generator.yml" "$tmp/.github/workflows/"
  cp "$ROOT/.actrc" "$tmp/"
  cp "$fixture" "$tmp/config.json"

  git -C "$tmp" init -q -b main
  git -C "$tmp" add -A
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci commit -qm "act test case: $name"

  # Run the whole pipeline through act. --pull=false keeps act on the
  # locally available runner image (mapped via .actrc).
  local out rc
  out="$tmp/act-output.txt"
  (cd "$tmp" && act push --rm --pull=false) > "$out" 2>&1
  rc=$?

  # Preserve the raw output as a required artifact, clearly delimited.
  {
    echo "================================================================"
    echo "=== ACT TEST CASE: $name (fixture: $(basename "$fixture"))"
    echo "=== act exit code: $rc"
    echo "================================================================"
    cat "$out"
    echo
  } >> "$RESULT_FILE"

  # Assertion 1: act must exit 0.
  if [[ $rc -eq 0 ]]; then
    pass "act exited 0"
  else
    fail "act exited $rc (see act-result.txt)"
  fi

  # Assertion 2: the generator emitted the EXACT expected strategy JSON.
  if grep -qF "MATRIX_RESULT=$expected_strategy" "$out"; then
    pass "exact matrix JSON found"
  else
    fail "expected exact 'MATRIX_RESULT=$expected_strategy' in act output"
  fi

  # Assertion 3: every expected matrix combination was built, exactly.
  local line
  for line in "${expected_lines[@]}"; do
    if grep -qF "$line" "$out"; then
      pass "found build line: $line"
    else
      fail "missing build line: $line"
    fi
  done

  # Assertion 4: no unexpected extra build combinations ran.
  local combo_count
  combo_count="$(grep -cF 'BUILD_COMBO os=' "$out")"
  if [[ "$combo_count" -eq "${#expected_lines[@]}" ]]; then
    pass "exactly ${#expected_lines[@]} build combinations ran"
  else
    fail "expected ${#expected_lines[@]} BUILD_COMBO lines, got $combo_count"
  fi

  # Assertion 5: every job reports success.
  local succeeded
  succeeded="$(grep -c 'Job succeeded' "$out")"
  if [[ "$succeeded" -eq "$expected_jobs" ]]; then
    pass "all $expected_jobs jobs report 'Job succeeded'"
  else
    fail "expected $expected_jobs 'Job succeeded' lines, got $succeeded"
  fi

  rm -rf "$tmp"
}

# --- Case 1: full-featured default config ---------------------------------
# config.json: 2 os x 2 versions x 1 flag = 4 combos, exclude removes
# (macos-latest, 3.11), include adds (ubuntu-latest, 3.13, experimental)
# => 4 build jobs; plus unit_tests and generate_matrix = 6 jobs total.
run_case "full config with include/exclude, fail-fast=false, max-parallel=3" \
  "$ROOT/config.json" \
  '{"fail-fast":false,"max-parallel":3,"matrix":{"os":["ubuntu-latest","macos-latest"],"language-version":["3.11","3.12"],"feature-flag":["standard"],"include":[{"os":"ubuntu-latest","language-version":"3.13","feature-flag":"experimental"}],"exclude":[{"os":"macos-latest","language-version":"3.11"}]}}' \
  6 \
  "BUILD_COMBO os=ubuntu-latest lang=3.11 flag=standard" \
  "BUILD_COMBO os=ubuntu-latest lang=3.12 flag=standard" \
  "BUILD_COMBO os=macos-latest lang=3.12 flag=standard" \
  "BUILD_COMBO os=ubuntu-latest lang=3.13 flag=experimental"

# --- Case 2: minimal config, GHA defaults for fail-fast -------------------
# 1 os x 2 versions x 1 flag = 2 build jobs; + 2 pipeline jobs = 4 total.
run_case "minimal config with default fail-fast=true, max-parallel=2" \
  "$ROOT/test/fixtures/act-case2.json" \
  '{"fail-fast":true,"max-parallel":2,"matrix":{"os":["ubuntu-latest"],"language-version":["18","20"],"feature-flag":["prod"]}}' \
  4 \
  "BUILD_COMBO os=ubuntu-latest lang=18 flag=prod" \
  "BUILD_COMBO os=ubuntu-latest lang=20 flag=prod"

log ""
if [[ $FAILURES -eq 0 ]]; then
  log "ALL ACT TEST CASES PASSED (results in act-result.txt)"
  exit 0
else
  log "$FAILURES ASSERTION(S) FAILED (results in act-result.txt)"
  exit 1
fi
