#!/usr/bin/env bats
#
# End-to-end workflow tests: every assertion here is made against output
# produced by running the GitHub Actions workflow inside Docker via `act`.
#
# For each fixture case we:
#   1. Build a temp git repo containing the project + that case's fixtures
#      (staged as the workflow's default `fixtures/` directory, since a
#      plain `push` event doesn't carry workflow_dispatch inputs).
#   2. Run `act push --rm`, capturing all output.
#   3. Append the output to act-result.txt (the required artifact), delimited.
#   4. Assert act exited 0, every job shows "Job succeeded", and the parsed
#      metrics match that case's known-good EXACT values.
#
# NOTE: each act run takes ~30-90s. Keep the case list small (<= 3 total runs).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export REPO_ROOT
  export ACT_RESULT="$REPO_ROOT/act-result.txt"
  : > "$ACT_RESULT"
}

# run_case <case-name> <artifacts-dir-name>
# Build an isolated repo containing BOTH fixture sets unmodified (fixtures/
# for case A and the unit-test suite, fixtures-caseB/ for case B), point the
# workflow's default ARTIFACTS_DIR at the requested one for this case, run
# the workflow via act, append output to the artifact, and leave results in
# globals for the calling test: ACT_RC, ACT_OUTPUT.
run_case() {
  local case_name="$1" artifacts_dir_name="$2"
  local work
  work="$(mktemp -d)"

  cp "$REPO_ROOT/artifact_cleanup.sh" "$work/"
  cp "$REPO_ROOT/test_artifact_cleanup.bats" "$work/"
  mkdir -p "$work/.github/workflows"
  cp "$REPO_ROOT/.github/workflows/artifact-cleanup-script.yml" "$work/.github/workflows/"
  [ -f "$REPO_ROOT/.actrc" ] && cp "$REPO_ROOT/.actrc" "$work/.actrc"

  cp -r "$REPO_ROOT/fixtures" "$work/fixtures"
  cp -r "$REPO_ROOT/fixtures-caseB" "$work/fixtures-caseB"

  # Point the workflow's default ARTIFACTS_DIR at this case's directory
  # (a plain `push` event carries no workflow_dispatch inputs to override it).
  sed -i "s#github.event.inputs.artifacts_dir || 'fixtures'#github.event.inputs.artifacts_dir || '${artifacts_dir_name}'#" \
    "$work/.github/workflows/artifact-cleanup-script.yml"

  (
    cd "$work" || exit 1
    git init -q
    git config user.email ci@example.com
    git config user.name CI
    git add -A
    git commit -qm "act case: $case_name"
  )

  local out rc
  set +e
  out="$(cd "$work" && act push --rm --pull=false 2>&1)"
  rc=$?
  set -e

  {
    echo "########################################################################"
    echo "# ACT CASE: ${case_name}   (exit code: ${rc})"
    echo "########################################################################"
    printf '%s\n' "$out"
    echo ""
  } >> "$ACT_RESULT"

  ACT_RC="$rc"
  ACT_OUTPUT="$out"
  rm -rf "$work"
}

# assert_jobs_succeeded — all three jobs (test, cleanup, report) succeeded.
assert_jobs_succeeded() {
  local n
  n="$(printf '%s\n' "$ACT_OUTPUT" | grep -c 'Job succeeded' || true)"
  [ "$n" -ge 3 ] || {
    echo "expected >=3 'Job succeeded', got $n"
    return 1
  }
}

@test "act case A: default fixtures produce the exact known cleanup plan" {
  run_case "A-default-fixtures" "fixtures"

  [ "$ACT_RC" -eq 0 ]
  assert_jobs_succeeded

  [[ "$ACT_OUTPUT" == *'"total_count":5'* ]]
  [[ "$ACT_OUTPUT" == *'"retained_count":2'* ]]
  [[ "$ACT_OUTPUT" == *'"deleted_count":3'* ]]
  [[ "$ACT_OUTPUT" == *'"retained_size_bytes":700'* ]]
  [[ "$ACT_OUTPUT" == *'"reclaimed_size_bytes":1800'* ]]
  [[ "$ACT_OUTPUT" == *"DELETE ci-old reason=max-age size_bytes=1000"* ]]
  [[ "$ACT_OUTPUT" == *"DELETE ci-run1 reason=keep-latest-n size_bytes=400"* ]]
  [[ "$ACT_OUTPUT" == *"DELETE ci-run2 reason=max-total-size size_bytes=400"* ]]
  [[ "$ACT_OUTPUT" == *"FINAL_SUMMARY total=5 retained=2 deleted=3 reclaimed_bytes=1800"* ]]
}

@test "act case B: dry-run policy produces the exact known dry-run plan" {
  run_case "B-dry-run" "fixtures-caseB"

  [ "$ACT_RC" -eq 0 ]
  assert_jobs_succeeded

  [[ "$ACT_OUTPUT" == *'"dry_run":true'* ]]
  [[ "$ACT_OUTPUT" == *'"total_count":3'* ]]
  [[ "$ACT_OUTPUT" == *'"retained_count":1'* ]]
  [[ "$ACT_OUTPUT" == *'"deleted_count":2'* ]]
  [[ "$ACT_OUTPUT" == *'"reclaimed_size_bytes":200'* ]]
  [[ "$ACT_OUTPUT" == *"[DRY-RUN] DELETE b1 reason=keep-latest-n size_bytes=100"* ]]
  [[ "$ACT_OUTPUT" == *"[DRY-RUN] DELETE b2 reason=keep-latest-n size_bytes=100"* ]]
  [[ "$ACT_OUTPUT" == *"FINAL_SUMMARY total=3 retained=1 deleted=2 reclaimed_bytes=200"* ]]
}

@test "act-result.txt artifact exists and contains both cases" {
  [ -f "$ACT_RESULT" ]
  grep -q "ACT CASE: A-default-fixtures" "$ACT_RESULT"
  grep -q "ACT CASE: B-dry-run" "$ACT_RESULT"
}
