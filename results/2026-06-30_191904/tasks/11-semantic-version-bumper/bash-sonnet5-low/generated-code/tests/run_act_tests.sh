#!/usr/bin/env bash
# run_act_tests.sh
#
# Drives the semantic-version-bumper workflow through `act push` for several
# fixture-driven test cases, capturing all output into act-result.txt and
# asserting exact expected version numbers + job success.
#
# The workflow hardcodes COMMITS_FILE=tests/fixtures/commits_mixed.txt, so
# each test case overwrites that fixture's *content* in an isolated temp git
# repo before invoking act, then asserts on the emitted "New version is X".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${REPO_ROOT}/act-result.txt"
: > "$RESULT_FILE"

# name : source fixture (relative to REPO_ROOT) : expected new version
CASES=(
  "fix_only:tests/fixtures/commits_fix_only.txt:1.2.4"
  "feat_only:tests/fixtures/commits_feat_only.txt:1.3.0"
  "breaking_bang:tests/fixtures/commits_bang_breaking.txt:2.0.0"
)

overall_status=0

for case_spec in "${CASES[@]}"; do
  IFS=':' read -r name fixture expected <<< "$case_spec"

  echo "===== TEST CASE: ${name} (expected new version: ${expected}) =====" | tee -a "$RESULT_FILE"

  tmpdir="$(mktemp -d)"
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/tests" "$REPO_ROOT/.github" "$tmpdir/"

  # Inject this case's commit messages into the CI-only fixture path the
  # workflow reads, without touching the fixtures the bats unit tests use.
  cp "$REPO_ROOT/$fixture" "$tmpdir/tests/fixtures/ci_commits.txt"

  (
    cd "$tmpdir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -q -m "test case ${name}"
  )

  set +e
  act_output="$(cd "$tmpdir" && act push --rm 2>&1)"
  act_status=$?
  set -e

  {
    echo "--- act exit code: ${act_status} ---"
    echo "$act_output"
    echo "===== END TEST CASE: ${name} ====="
    echo
  } >> "$RESULT_FILE"

  rm -rf "$tmpdir"

  if [ "$act_status" -ne 0 ]; then
    echo "FAIL [${name}]: act exited with status ${act_status}" >&2
    overall_status=1
    continue
  fi

  jobs_succeeded="$(grep -c "Job succeeded" <<< "$act_output" || true)"
  if [ "$jobs_succeeded" -lt 2 ]; then
    echo "FAIL [${name}]: expected 2 'Job succeeded' lines (test + bump jobs), got ${jobs_succeeded}" >&2
    overall_status=1
    continue
  fi

  if ! grep -q "New version is ${expected}" <<< "$act_output"; then
    echo "FAIL [${name}]: expected exact output 'New version is ${expected}' not found" >&2
    overall_status=1
    continue
  fi

  echo "PASS [${name}]: got exact expected version ${expected}, both jobs succeeded"
done

exit $overall_status
