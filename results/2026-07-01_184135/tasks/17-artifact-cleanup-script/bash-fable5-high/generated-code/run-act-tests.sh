#!/usr/bin/env bash
#
# run-act-tests.sh — execute every test case through the GitHub Actions
# workflow via act (nektos/act) and assert on exact expected values.
#
# Approach: a temp git repo is staged with the project files plus ALL fixture
# data, and a single `act push --rm` run executes the whole pipeline: the
# lint job (bash -n + shellcheck), the full bats unit suite, and four
# delimited scenario cases. One act invocation covers every case because act
# runs are budgeted (max 3); each case is still asserted individually below
# against its known-good output.
#
# Output: act-result.txt in this directory (required artifact).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT="$ROOT/act-result.txt"
ACT_IMAGE="ghcr.io/catthehacker/ubuntu:act-latest"

fail() { echo "HARNESS FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Stage a temp git repo with the project files + fixture data
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/test" "$TMP/.github/workflows"
cp "$ROOT/artifact-cleanup.sh" "$TMP/"
cp "$ROOT/test/artifact_cleanup.bats" "$TMP/test/"
cp -r "$ROOT/test/fixtures" "$TMP/test/fixtures"
cp "$ROOT/.github/workflows/artifact-cleanup-script.yml" "$TMP/.github/workflows/"

git -C "$TMP" init -q
git -C "$TMP" -c user.email=ci@example.com -c user.name=ci add -A
git -C "$TMP" -c user.email=ci@example.com -c user.name=ci \
  commit -qm "act test fixture repo"

# ---------------------------------------------------------------------------
# 2. Run the workflow through act, capturing all output
# ---------------------------------------------------------------------------
echo "Running act push (this takes a minute)..."
set +e
(cd "$TMP" && act push --rm -P "ubuntu-latest=$ACT_IMAGE" --pull=false) \
  >"$TMP/act-output.txt" 2>&1
ACT_EXIT=$?
set -e

{
  echo "================================================================"
  echo "=== ACT RUN: all test cases (event=push) exit_code=$ACT_EXIT ==="
  echo "================================================================"
  cat "$TMP/act-output.txt"
} >"$RESULT"

# ---------------------------------------------------------------------------
# 3. Assert act succeeded and both jobs report success
# ---------------------------------------------------------------------------
[ "$ACT_EXIT" -eq 0 ] || fail "act exited with code $ACT_EXIT (see act-result.txt)"
echo "ok: act exited 0"

grep -q '\[artifact-cleanup-script/lint\].*Job succeeded' "$RESULT" \
  || fail "lint job did not report 'Job succeeded'"
grep -q '\[artifact-cleanup-script/test\].*Job succeeded' "$RESULT" \
  || fail "test job did not report 'Job succeeded'"
echo "ok: both jobs report 'Job succeeded'"

# ---------------------------------------------------------------------------
# 4. Per-case assertions on EXACT expected values
# ---------------------------------------------------------------------------
CHECKS=0
expect() { # expect CASE LITERAL — the act output must contain LITERAL exactly
  local case_name="$1" needle="$2"
  grep -Fq -- "$needle" "$RESULT" \
    || fail "[$case_name] missing expected output: ${needle@Q}"
  CHECKS=$((CHECKS + 1))
}

# Sanity: the bats suite ran inside the pipeline and every test passed.
expect bats-suite '1..17'
if grep -q 'not ok' "$RESULT"; then
  fail "bats suite inside act reported failing tests"
fi

# Case 1: age.tsv, --max-age-days 30, dry-run.
# build-logs (62d) and coverage (92d) exceed 30 days; test-report (7d) stays.
expect max-age '=== CASE:max-age ==='
expect max-age "$(printf 'DELETE\tbuild-logs\t1000\tmax-age')"
expect max-age "$(printf 'DELETE\tcoverage\t500\tmax-age')"
expect max-age "$(printf 'KEEP\ttest-report\t2000')"
expect max-age 'SUMMARY: retained=1 deleted=2 reclaimed_bytes=1500 retained_bytes=2000'
expect max-age 'DRY-RUN: no artifacts were deleted'

# Case 2: keepn.tsv, --keep-latest 2, dry-run.
# Run 200 keeps its 2 newest (nightly-b/c), evicts nightly-a; run 300 intact.
expect keep-latest '=== CASE:keep-latest ==='
expect keep-latest "$(printf 'DELETE\tnightly-a\t100\tkeep-latest')"
expect keep-latest "$(printf 'KEEP\tnightly-b\t100')"
expect keep-latest "$(printf 'KEEP\tnightly-c\t100')"
expect keep-latest "$(printf 'KEEP\trelease-a\t100')"
expect keep-latest 'SUMMARY: retained=3 deleted=1 reclaimed_bytes=100 retained_bytes=300'

# Case 3: size.tsv, --max-total-size 6000, dry-run.
# Total 9000 -> evict oldest (old-big, 4000) -> 5000 retained.
expect size-budget '=== CASE:size-budget ==='
expect size-budget "$(printf 'DELETE\told-big\t4000\tmax-total-size')"
expect size-budget "$(printf 'KEEP\tmid\t3000')"
expect size-budget "$(printf 'KEEP\tnew\t2000')"
expect size-budget 'SUMMARY: retained=2 deleted=1 reclaimed_bytes=4000 retained_bytes=5000'

# Case 4: combined.tsv, all three policies, APPLY mode with mock deletion log.
# max-age evicts ci-logs-old, keep-latest evicts ci-bin-old, size budget
# evicts ci-logs-new; the deletion log records the three ids in input order.
expect combined '=== CASE:combined ==='
expect combined "$(printf 'DELETE\tci-logs-old\t1500\tmax-age')"
expect combined "$(printf 'DELETE\tci-bin-old\t2500\tkeep-latest')"
expect combined "$(printf 'DELETE\tci-logs-new\t2000\tmax-total-size')"
expect combined "$(printf 'KEEP\tci-bin\t3000')"
expect combined "$(printf 'KEEP\tdocs\t1000')"
expect combined 'SUMMARY: retained=2 deleted=3 reclaimed_bytes=6000 retained_bytes=4000'
expect combined 'Deleted 3 artifact(s)'
expect combined "$(printf '1\tci-logs-old')"
expect combined "$(printf '2\tci-logs-new')"
expect combined "$(printf '4\tci-bin-old')"

echo "ok: all $CHECKS exact-value assertions passed"
echo "PASS: act pipeline verified; full log in act-result.txt"
