#!/usr/bin/env bash
# End-to-end pipeline test harness.
#
# For each test case this script:
#   1. Builds a temp git repo containing the project files plus the
#      case-specific fixture data under data/ (the workflow prefers
#      data/* over its bundled fallback fixtures).
#   2. Runs the GitHub Actions workflow locally with `act push --rm`.
#   3. Appends the full act output to act-result.txt (delimited).
#   4. Asserts act exited 0, both jobs report "Job succeeded", and the
#      report contains the EXACT expected per-dependency lines.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
: > "$RESULT_FILE"

FAILURES=0

fail() {
  echo "ASSERTION FAILED: $*" >&2
  FAILURES=$((FAILURES + 1))
}

# assert_contains <haystack-file> <exact-expected-line-fragment>
assert_contains() {
  local file=$1 expected=$2
  if grep -qF "$expected" "$file"; then
    echo "  PASS: output contains '$expected'"
  else
    fail "output missing expected text: '$expected'"
  fi
}

# run_case <case-name> <manifest-fixture> <manifest-dest-name> <expected...>
run_case() {
  local case_name=$1 manifest_src=$2 manifest_dest=$3
  shift 3

  echo "=== CASE: $case_name ==="
  local tmp
  tmp=$(mktemp -d)

  # Assemble the project + per-case fixture data in an isolated repo.
  mkdir -p "$tmp/data"
  cp -r "$PROJECT_DIR/license_checker.sh" "$PROJECT_DIR/test" \
        "$PROJECT_DIR/.github" "$PROJECT_DIR/.actrc" "$tmp/"
  cp "$manifest_src" "$tmp/data/$manifest_dest"
  cp "$PROJECT_DIR/test/fixtures/policy.conf" "$tmp/data/policy.conf"
  cp "$PROJECT_DIR/test/fixtures/licenses.db" "$tmp/data/licenses.db"

  git -C "$tmp" init -q
  git -C "$tmp" -c user.email=ci@test -c user.name=ci add -A
  git -C "$tmp" -c user.email=ci@test -c user.name=ci commit -qm "case: $case_name"

  # Run the workflow through act and capture everything.
  local out="$tmp/act-output.txt" rc
  # --pull=false: the runner image is local-only; pulling would fail.
  (cd "$tmp" && act push --rm --pull=false >"$out" 2>&1)
  rc=$?

  {
    echo "================================================================"
    echo "=== TEST CASE: $case_name (act exit code: $rc)"
    echo "================================================================"
    cat "$out"
    echo
  } >> "$RESULT_FILE"

  if [ "$rc" -eq 0 ]; then
    echo "  PASS: act exited 0"
  else
    fail "[$case_name] act exited with code $rc"
  fi

  # Both jobs (test + compliance-report) must succeed.
  local succeeded
  succeeded=$(grep -c 'Job succeeded' "$out")
  if [ "$succeeded" -ge 2 ]; then
    echo "  PASS: both jobs report 'Job succeeded' ($succeeded)"
  else
    fail "[$case_name] expected 2 'Job succeeded' lines, got $succeeded"
  fi

  # Exact-value assertions on the report output.
  local expected
  for expected in "$@"; do
    assert_contains "$out" "$expected"
  done

  rm -rf "$tmp"
}

# --- Case 1: package.json with approved, denied and unknown licenses --------
run_case "package.json mixed licenses" \
  "$PROJECT_DIR/test/fixtures/package.json" "package.json" \
  "left-pad 1.3.0 MIT approved" \
  "evil-lib 2.0.0 GPL-3.0 denied" \
  "mystery-pkg 0.1.0 UNKNOWN unknown" \
  "SUMMARY: total=3 approved=1 denied=1 unknown=1"

# --- Case 2: requirements.txt where every license is allow-listed -----------
run_case "requirements.txt all approved" \
  "$PROJECT_DIR/test/fixtures/requirements.txt" "requirements.txt" \
  "requests 2.31.0 Apache-2.0 approved" \
  "flask 3.0.2 BSD-3-Clause approved" \
  "left-pad 1.3.0 MIT approved" \
  "SUMMARY: total=3 approved=3 denied=0 unknown=0"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT PIPELINE TESTS PASSED (results in act-result.txt)"
else
  echo "$FAILURES assertion(s) failed (see act-result.txt)" >&2
  exit 1
fi
