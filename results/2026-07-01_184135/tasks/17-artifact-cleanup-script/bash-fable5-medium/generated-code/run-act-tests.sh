#!/usr/bin/env bash
# Act-based end-to-end test harness.
#
# For each test case it builds a temp git repo containing the project files
# plus that case's fixture data (ci-fixtures/artifacts.tsv + policy.env),
# runs `act push --rm`, appends the output to act-result.txt, and asserts:
#   - act exited 0
#   - both jobs report "Job succeeded"
#   - the deletion plan contains the EXACT expected values for that input
# It also runs the workflow structure checks (bats + actionlint) on the host.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT="$ROOT/act-result.txt"
WF=".github/workflows/artifact-cleanup-script.yml"
: > "$RESULT"

PASS=0
FAIL=0

check() { # check <description> — asserts previous command's captured condition
  local desc="$1" ok="$2"
  if [[ "$ok" == "0" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() { # assert_contains <file> <needle> <description>
  grep -qF -- "$2" "$1"; check "$3" "$?"
}

# --- host-side workflow structure tests --------------------------------------
echo "== Workflow structure tests (host) =="
actionlint "$ROOT/$WF"; check "actionlint exits 0" "$?"
bats "$ROOT/tests/workflow.bats"; check "workflow structure bats suite passes" "$?"

# --- act test cases -----------------------------------------------------------
# run_case <name> <artifacts-tsv-content> <policy-env-content>
run_case() {
  local name="$1" artifacts="$2" policy="$3"
  local tmp
  tmp="$(mktemp -d)"
  echo "== act case: $name =="
  # Assemble the temp repo: project files + case-specific fixtures
  cp -r "$ROOT/.github" "$ROOT/ci" "$ROOT/tests" "$ROOT/artifact-cleanup.sh" "$tmp/"
  [[ -f "$ROOT/.actrc" ]] && cp "$ROOT/.actrc" "$tmp/"
  mkdir -p "$tmp/ci-fixtures"
  printf '%s' "$artifacts" > "$tmp/ci-fixtures/artifacts.tsv"
  printf '%s' "$policy" > "$tmp/ci-fixtures/policy.env"
  (
    cd "$tmp" || exit 1
    git init -q
    git -c user.email=ci@example.com -c user.name=ci add -A
    git -c user.email=ci@example.com -c user.name=ci commit -qm "test case: $name"
  )
  {
    echo "=============================================================="
    echo "=== ACT CASE: $name"
    echo "=============================================================="
  } >> "$RESULT"
  # --pull=false: the runner image only exists locally; a forced pull fails
  (cd "$tmp" && act push --rm --pull=false) >> "$RESULT" 2>&1
  local rc=$?
  check "act exited 0 for case '$name'" "$rc"
  rm -rf "$tmp"
}

CASE1_ARTIFACTS=$'ancient\t9000\t2026-01-01T00:00:00Z\t100\ndup-old\t3000\t2026-06-10T00:00:00Z\t100\ndup-new\t1000\t2026-06-20T00:00:00Z\t100\nbig-old\t4000\t2026-06-15T00:00:00Z\t200\nsmall-new\t2000\t2026-06-25T00:00:00Z\t300\n'
CASE1_POLICY=$'POLICY_NOW=2026-07-01T00:00:00Z\nPOLICY_MAX_AGE_DAYS=30\nPOLICY_KEEP_LATEST=1\nPOLICY_MAX_TOTAL_SIZE=5000\nPOLICY_DRY_RUN=1\n'

CASE2_ARTIFACTS=$'r100-a1\t100\t2026-06-01T00:00:00Z\t100\nr100-a2\t200\t2026-06-10T00:00:00Z\t100\nr100-a3\t300\t2026-06-20T00:00:00Z\t100\nr200-a1\t400\t2026-06-05T00:00:00Z\t200\n'
CASE2_POLICY=$'POLICY_NOW=2026-07-01T00:00:00Z\nPOLICY_KEEP_LATEST=2\nPOLICY_DRY_RUN=0\n'

run_case "combined-policies-dry-run" "$CASE1_ARTIFACTS" "$CASE1_POLICY"
# Slice case 1's output for exact-value assertions
CASE1_LOG="$(mktemp)"
awk '/=== ACT CASE: combined-policies-dry-run/{f=1} /=== ACT CASE: keep-latest-real-mode/{f=0} f' \
  "$RESULT" > "$CASE1_LOG"

run_case "keep-latest-real-mode" "$CASE2_ARTIFACTS" "$CASE2_POLICY"
CASE2_LOG="$(mktemp)"
awk '/=== ACT CASE: keep-latest-real-mode/{f=1} f' "$RESULT" > "$CASE2_LOG"

echo "== exact-value assertions: case 1 (combined policies, dry-run) =="
assert_contains "$CASE1_LOG" $'DELETE\tancient\t9000\tmax-age'          "ancient deleted by max-age"
assert_contains "$CASE1_LOG" $'DELETE\tdup-old\t3000\tkeep-latest'      "dup-old deleted by keep-latest"
assert_contains "$CASE1_LOG" $'DELETE\tbig-old\t4000\tmax-total-size'   "big-old deleted by max-total-size"
assert_contains "$CASE1_LOG" $'RETAIN\tdup-new\t1000'                   "dup-new retained"
assert_contains "$CASE1_LOG" $'RETAIN\tsmall-new\t2000'                 "small-new retained"
assert_contains "$CASE1_LOG" "Artifacts retained: 2"                    "retained count is exactly 2"
assert_contains "$CASE1_LOG" "Artifacts deleted: 3"                     "deleted count is exactly 3"
assert_contains "$CASE1_LOG" "Space reclaimed: 16000 bytes"             "space reclaimed is exactly 16000"
assert_contains "$CASE1_LOG" "DRY-RUN: no artifacts were deleted"       "dry-run notice present"
n=$(grep -c "Job succeeded" "$CASE1_LOG")
if [[ $n -eq 2 ]]; then ok=0; else ok=1; fi
check "both jobs succeeded in case 1 (got $n)" "$ok"

echo "== exact-value assertions: case 2 (keep-latest 2, real mode) =="
assert_contains "$CASE2_LOG" $'DELETE\tr100-a1\t100\tkeep-latest'       "r100-a1 deleted by keep-latest"
assert_contains "$CASE2_LOG" $'RETAIN\tr100-a2\t200'                    "r100-a2 retained"
assert_contains "$CASE2_LOG" $'RETAIN\tr100-a3\t300'                    "r100-a3 retained"
assert_contains "$CASE2_LOG" $'RETAIN\tr200-a1\t400'                    "r200-a1 retained (only artifact in run)"
assert_contains "$CASE2_LOG" "Artifacts retained: 3"                    "retained count is exactly 3"
assert_contains "$CASE2_LOG" "Artifacts deleted: 1"                     "deleted count is exactly 1"
assert_contains "$CASE2_LOG" "Space reclaimed: 100 bytes"               "space reclaimed is exactly 100"
assert_contains "$CASE2_LOG" "Deleting artifact: r100-a1"               "real mode performed the mock deletion"
n=$(grep -c "Job succeeded" "$CASE2_LOG")
if [[ $n -eq 2 ]]; then ok=0; else ok=1; fi
check "both jobs succeeded in case 2 (got $n)" "$ok"

rm -f "$CASE1_LOG" "$CASE2_LOG"

echo
echo "== Harness summary: $PASS passed, $FAIL failed =="
[[ $FAIL -eq 0 ]] || exit 1
exit 0
