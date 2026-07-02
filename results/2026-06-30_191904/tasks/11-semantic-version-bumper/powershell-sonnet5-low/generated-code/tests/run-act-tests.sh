#!/usr/bin/env bash
# Test harness that runs the semantic-version-bumper workflow through `act`
# for three fixture scenarios (feat/minor, fix/patch, breaking/major), each in
# its own temp git repo, and asserts on exact expected version output.
#
# Usage: tests/run-act-tests.sh   (run from the repo root)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
: > "$RESULT_FILE"

# case name | initial version | commit fixture file | expected new version | expected bump type
CASES=(
  "feat-minor|1.1.0|commits-feat.txt|1.2.0|minor"
  "fix-patch|2.0.0|commits-fix.txt|2.0.1|patch"
  "breaking-major|1.5.2|commits-breaking.txt|2.0.0|major"
)

overall_status=0

for case_def in "${CASES[@]}"; do
  IFS='|' read -r name initial_version commit_fixture expected_version expected_bump <<< "$case_def"

  echo "==== running act test case: $name ===="

  tmp_repo="$(mktemp -d)"
  trap 'rm -rf "$tmp_repo"' EXIT

  # Copy the whole project (script, module, tests, workflow, fixtures) into the temp repo
  cp -R "$REPO_ROOT"/. "$tmp_repo"/
  rm -rf "$tmp_repo/.git" "$tmp_repo/act-result.txt"

  # Overwrite the fixture files the workflow reads so this case's scenario is exercised
  printf '{\n  "name": "demo-app",\n  "version": "%s"\n}\n' "$initial_version" > "$tmp_repo/fixtures/demo-package.json"

  (
    cd "$tmp_repo"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -q -m "test case $name"
  )

  {
    echo "########## TEST CASE: $name (initial=$initial_version expected=$expected_version bump=$expected_bump) ##########"
  } >> "$RESULT_FILE"

  set +e
  act_output="$(cd "$tmp_repo" && act push --rm --env "COMMIT_FIXTURE=$commit_fixture" 2>&1)"
  act_exit=$?
  set -e

  echo "$act_output" >> "$RESULT_FILE"
  echo "ACT_EXIT_CODE=$act_exit" >> "$RESULT_FILE"
  echo "########## END TEST CASE: $name ##########" >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"

  case_status=0

  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$name]: act exited with code $act_exit"
    case_status=1
  fi

  if ! grep -q "Job succeeded" <<< "$act_output"; then
    echo "FAIL [$name]: 'Job succeeded' not found in act output"
    case_status=1
  fi

  if ! grep -q "NewVersion=$expected_version" <<< "$act_output"; then
    echo "FAIL [$name]: expected NewVersion=$expected_version not found in act output"
    case_status=1
  fi

  if ! grep -q "BumpType=$expected_bump" <<< "$act_output"; then
    echo "FAIL [$name]: expected BumpType=$expected_bump not found in act output"
    case_status=1
  fi

  if [ "$case_status" -eq 0 ]; then
    echo "PASS [$name]: exit=0, Job succeeded, NewVersion=$expected_version, BumpType=$expected_bump"
  else
    overall_status=1
  fi

  rm -rf "$tmp_repo"
  trap - EXIT
done

echo ""
if [ "$overall_status" -eq 0 ]; then
  echo "ALL ACT TEST CASES PASSED"
else
  echo "ONE OR MORE ACT TEST CASES FAILED"
fi

exit $overall_status
