#!/usr/bin/env bash
# End-to-end pipeline tests: every test case runs through the GitHub Actions
# workflow via `act` (never by invoking the script directly).
#
# Per case:
#   1. build a temp git repo = project files + that case's manifest fixture,
#   2. run `act push --rm`, appending output to act-result.txt (delimited),
#   3. assert act exit code 0, both jobs "Job succeeded", the unit-test pass
#      count, and the EXACT report lines expected for that fixture.
#
# Modes:
#   ./run-act-tests.sh                # full run: act per case + assertions
#   ./run-act-tests.sh --assert-only  # re-run all assertions against the act
#                                     # output already captured in
#                                     # act-result.txt (no new act runs)
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
MODE="${1:-run}"

if [ "$MODE" = "run" ]; then
  : > "$RESULT_FILE"
elif [ ! -f "$RESULT_FILE" ]; then
  echo "error: --assert-only needs an existing $RESULT_FILE (run without flags first)"
  exit 1
fi

FAILURES=0

fail() { echo "ASSERT FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "ok - $1"; }

# assert_contains <output-file> <exact-fixed-string>
assert_contains() {
  if grep -qF -- "$2" "$1"; then pass "output contains: $2"; else fail "output missing: $2"; fi
}

# All assertions for one case, against a file holding that case's act output.
# "pass 19"/"fail 0" (no prefix) match both node:test reporters: TAP
# ("# pass 19") and spec ("ℹ pass 19", used by Node 24 in the act container).
assert_case() {
  local out="$1" code="$2"
  shift 2
  local expected_lines=("$@")

  if [ "$code" -eq 0 ]; then pass "act exit code 0"; else fail "act exit code $code (want 0)"; fi

  # Both jobs (test, license-check) must report success.
  local ok_jobs
  ok_jobs=$(grep -c "Job succeeded" "$out")
  if [ "$ok_jobs" -eq 2 ]; then pass "2 jobs succeeded"; else fail "expected 2 'Job succeeded', got $ok_jobs"; fi

  # Unit test suite ran inside the pipeline with the exact expected counts.
  assert_contains "$out" "tests 19"
  assert_contains "$out" "pass 19"
  assert_contains "$out" "fail 0"

  local line
  for line in "${expected_lines[@]}"; do
    assert_contains "$out" "$line"
  done
}

run_case() {
  local case_name="$1" fixture_dir="$2"
  shift 2
  local expected_lines=("$@")

  echo ""
  echo "=== CASE: $case_name ==="

  if [ "$MODE" = "--assert-only" ]; then
    # Extract this case's section (delimited in act-result.txt) and its
    # recorded exit code, then run the same assertions on it.
    local out code
    out="$(mktemp)"
    awk -v name="$case_name" '
      /^=== TEST CASE: / { current = (index($0, name) > 0) }
      current' "$RESULT_FILE" > "$out"
    code=$(grep -m1 '^=== act exit code: ' "$out" | sed 's/[^0-9]//g')
    if [ ! -s "$out" ] || [ -z "$code" ]; then
      fail "no captured output for case '$case_name' in act-result.txt"
      rm -f "$out"
      return
    fi
    assert_case "$out" "$code" "${expected_lines[@]}"
    rm -f "$out"
    return
  fi

  local tmp
  tmp="$(mktemp -d)"

  # Project files the workflow needs, plus .actrc so act picks the same
  # runner image inside the temp repo.
  cp "$ROOT"/license-checker.js "$ROOT"/license-checker.test.js \
     "$ROOT"/checker-config.json "$ROOT"/mock-licenses.json "$ROOT"/.actrc "$tmp/"
  mkdir -p "$tmp/.github/workflows" "$tmp/test-manifest"
  cp "$ROOT/.github/workflows/dependency-license-checker.yml" "$tmp/.github/workflows/"
  cp "$ROOT/$fixture_dir"/* "$tmp/test-manifest/"

  git -C "$tmp" init -q
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci commit -qm "fixture: $case_name"

  local out="$tmp/act-output.txt"
  (cd "$tmp" && act push --rm --pull=false >"$out" 2>&1)
  local code=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $case_name (fixture: $fixture_dir) ==="
    echo "=== act exit code: $code ==="
    echo "================================================================"
    cat "$out"
    echo ""
  } >> "$RESULT_FILE"

  assert_case "$out" "$code" "${expected_lines[@]}"

  rm -rf "$tmp"
}

# Case 1: Node manifest. express/lodash MIT -> approved, gpl-tool GPL-3.0 ->
# denied, mystery-lib absent from the mock DB -> unknown.
run_case "package.json manifest" "fixtures/case1-package-json" \
  "Manifest type: package.json" \
  "express@4.18.2 | MIT | APPROVED" \
  "gpl-tool@1.0.0 | GPL-3.0 | DENIED" \
  "lodash@4.17.21 | MIT | APPROVED" \
  "mystery-lib@0.0.1 | UNKNOWN | UNKNOWN" \
  "Summary: 4 total, 2 approved, 1 denied, 1 unknown"

# Case 2: Python manifest. Apache/BSD -> approved, AGPL -> denied,
# totally-unknown-pkg unresolvable -> unknown; numpy has no pinned version.
run_case "requirements.txt manifest" "fixtures/case2-requirements-txt" \
  "Manifest type: requirements.txt" \
  "requests@2.31.0 | Apache-2.0 | APPROVED" \
  "flask@2.3.0 | BSD-3-Clause | APPROVED" \
  "numpy@unspecified | BSD-3-Clause | APPROVED" \
  "agpl-package@2.0.0 | AGPL-3.0 | DENIED" \
  "totally-unknown-pkg@0.1.0 | UNKNOWN | UNKNOWN" \
  "Summary: 5 total, 3 approved, 1 denied, 1 unknown"

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT PIPELINE TESTS PASSED (results in act-result.txt)"
  exit 0
else
  echo "$FAILURES ASSERTION(S) FAILED (see act-result.txt)"
  exit 1
fi
