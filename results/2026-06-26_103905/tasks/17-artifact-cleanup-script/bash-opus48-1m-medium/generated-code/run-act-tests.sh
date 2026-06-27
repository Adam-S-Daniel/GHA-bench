#!/usr/bin/env bash
#
# run-act-tests.sh — end-to-end test harness.
#
# For each test case this harness:
#   1. builds a throwaway git repo containing the project files plus that
#      case's fixture data (fixtures/artifacts.tsv + fixtures/policy.env),
#   2. runs the workflow with `act push --rm`,
#   3. appends the full act output to act-result.txt (clearly delimited),
#   4. asserts act exited 0,
#   5. asserts every job reports "Job succeeded",
#   6. parses the plan output and asserts EXACT expected values for that case.
#
# Each case is one `act push` run; there are 3 cases (the documented limit).

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="${PROJECT_DIR}/act-result.txt"

# Start with a fresh aggregate result file.
: > "$RESULT_FILE"

FAILURES=0

# clean_act_state — remove leftover containers/volumes for THIS workflow only.
# act derives deterministic container names from the workflow name, so a stuck
# container from a prior case collides ("name already in use"). We scope the
# filter to act-Artifact-Cleanup so we never touch other workspaces' containers.
clean_act_state() {
  docker ps -aq --filter "name=act-Artifact-Cleanup" \
    | xargs -r docker rm -f -v >/dev/null 2>&1 || true
  docker volume ls -q --filter "name=act-Artifact-Cleanup" \
    | xargs -r docker volume rm -f >/dev/null 2>&1 || true
}

# assert_contains HAYSTACK NEEDLE LABEL — substring assertion with reporting.
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label (expected to find: '$needle')"
    FAILURES=$((FAILURES + 1))
  fi
}

# run_case NAME ARTIFACTS_TSV POLICY_ENV — set up a repo, run act, capture out.
# Returns the captured output via the global CASE_OUTPUT / CASE_STATUS.
run_case() {
  local name="$1" artifacts="$2" policy="$3"
  local work
  work="$(mktemp -d)"

  echo "=================================================================="
  echo "TEST CASE: $name"
  echo "=================================================================="

  # Populate the throwaway repo with the project files + case fixtures.
  mkdir -p "$work/.github/workflows" "$work/tests" "$work/fixtures"
  cp "$PROJECT_DIR/artifact-cleanup.sh" "$work/"
  cp "$PROJECT_DIR/.github/workflows/artifact-cleanup-script.yml" "$work/.github/workflows/"
  cp "$PROJECT_DIR/tests/cleanup.bats" "$work/tests/"
  cp "$PROJECT_DIR/.actrc" "$work/" 2>/dev/null || true
  printf '%s' "$artifacts" > "$work/fixtures/artifacts.tsv"
  printf '%s' "$policy" > "$work/fixtures/policy.env"

  # act needs a git repo to discover the workflow.
  git -C "$work" init -q
  git -C "$work" config user.email ci@example.com
  git -C "$work" config user.name ci
  git -C "$work" add -A
  git -C "$work" commit -qm "test case: $name"

  # Run the workflow. Capture combined stdout+stderr.
  # Run act, retrying ONLY on known Docker daemon transients (overlay RWLayer
  # races / leftover-container name conflicts seen under concurrent load on
  # WSL2). A genuine workflow failure is surfaced immediately, never masked.
  # --pull=false: the runner image (act-ubuntu-pwsh:latest) is built locally
  # and has no registry, so act must use the local copy rather than pulling.
  # --bind: bind-mount the repo instead of `docker cp`-ing it into a named
  # volume; this sidesteps the flaky copy/volume-reuse step that fails under
  # daemon contention from concurrently-running workspaces.
  local transient='RWLayer of container|unexpectedly nil|No such container|is already in use|volume is in use|failed to copy content to container|error during connect'
  local attempt=0
  while : ; do
    attempt=$((attempt + 1))
    clean_act_state
    if CASE_OUTPUT="$(cd "$work" && act push --rm --pull=false --bind 2>&1)"; then
      CASE_STATUS=0
      break
    fi
    CASE_STATUS=$?
    if [ "$attempt" -lt 8 ] && grep -qE "$transient" <<< "$CASE_OUTPUT"; then
      echo "  (transient docker error on attempt $attempt, retrying...)"
      continue
    fi
    break
  done

  # Append to the aggregate result file, clearly delimited.
  {
    echo ""
    echo "########## ACT OUTPUT: $name (exit=$CASE_STATUS) ##########"
    echo "$CASE_OUTPUT"
    echo "########## END: $name ##########"
  } >> "$RESULT_FILE"

  rm -rf "$work"

  # Shared assertions: clean exit + every job succeeded.
  if [ "$CASE_STATUS" -eq 0 ]; then
    echo "  PASS: act exited 0"
  else
    echo "  FAIL: act exited $CASE_STATUS"
    FAILURES=$((FAILURES + 1))
  fi
  # Three jobs run -> expect three "Job succeeded" lines.
  local succeeded
  succeeded="$(grep -c "Job succeeded" <<< "$CASE_OUTPUT")"
  if [ "$succeeded" -ge 3 ]; then
    echo "  PASS: all 3 jobs succeeded ($succeeded 'Job succeeded')"
  else
    echo "  FAIL: expected >=3 'Job succeeded', got $succeeded"
    FAILURES=$((FAILURES + 1))
  fi
}

# Shared fixture used by every case.
ARTIFACTS=$'build-logs\t100\t1781568000\t1\nbuild-logs\t200\t1782000000\t1\ncoverage\t300\t1778976000\t2\n'

# ---- Case 1: max-age-days=30 -------------------------------------------
# coverage (40d old) is deleted; the two build-logs survive.
run_case "max-age-30" "$ARTIFACTS" \
$'MAX_AGE_DAYS=30\nKEEP_LATEST=\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=0\n'
assert_contains "$CASE_OUTPUT" "Total artifacts: 3"        "case1: total = 3"
assert_contains "$CASE_OUTPUT" "Retained: 2"               "case1: retained = 2"
assert_contains "$CASE_OUTPUT" "Deleted: 1"               "case1: deleted = 1"
assert_contains "$CASE_OUTPUT" "Space reclaimed: 300 bytes" "case1: reclaimed = 300"

# ---- Case 2: keep-latest=1 ---------------------------------------------
# run 1 keeps the newer build-logs (200) and deletes the older (100);
# run 2's single coverage survives.
run_case "keep-latest-1" "$ARTIFACTS" \
$'MAX_AGE_DAYS=\nKEEP_LATEST=1\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=0\n'
assert_contains "$CASE_OUTPUT" "Retained: 2"               "case2: retained = 2"
assert_contains "$CASE_OUTPUT" "Deleted: 1"               "case2: deleted = 1"
assert_contains "$CASE_OUTPUT" "Space reclaimed: 100 bytes" "case2: reclaimed = 100"

# ---- Case 3: combined age + keep-latest, dry-run -----------------------
# age>30 deletes coverage (300); keep-latest 1 deletes the older build-logs
# (100); only the newest build-logs (200) survives. Dry-run header present.
run_case "combined-dryrun" "$ARTIFACTS" \
$'MAX_AGE_DAYS=30\nKEEP_LATEST=1\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=1\n'
assert_contains "$CASE_OUTPUT" "DRY-RUN"                   "case3: dry-run marked"
assert_contains "$CASE_OUTPUT" "Retained: 1"               "case3: retained = 1"
assert_contains "$CASE_OUTPUT" "Deleted: 2"               "case3: deleted = 2"
assert_contains "$CASE_OUTPUT" "Space reclaimed: 400 bytes" "case3: reclaimed = 400"

echo ""
echo "=================================================================="
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT TESTS PASSED"
  exit 0
else
  echo "ACT TESTS FAILED: $FAILURES assertion(s) failed"
  exit 1
fi
