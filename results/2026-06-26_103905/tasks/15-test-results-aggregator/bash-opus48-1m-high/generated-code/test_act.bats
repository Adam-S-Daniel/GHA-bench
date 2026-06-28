#!/usr/bin/env bats
#
# End-to-end workflow tests: every assertion here is made against output
# produced by running the GitHub Actions workflow inside Docker via `act`.
#
# For each fixture case we:
#   1. Build a temp git repo containing the project + that case's fixtures.
#   2. Run `act push --rm`, capturing all output.
#   3. Append the output to act-result.txt (the required artifact), delimited.
#   4. Assert act exited 0, every job shows "Job succeeded", and the parsed
#      metrics match that case's known-good EXACT values.
#
# NOTE: each act run takes ~30-90s. Keep the case list small.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export REPO_ROOT
  export ACT_RESULT="$REPO_ROOT/act-result.txt"
  export ACT_IMAGE="act-ubuntu-pwsh:latest"
  # Start the artifact fresh for this run.
  : > "$ACT_RESULT"
}

# run_case <case-name> <fixtures-source-dir>
# Build an isolated repo, run the workflow via act, append output to the
# artifact, and leave results in globals for the calling test:
#   ACT_RC      — act exit code
#   ACT_OUTPUT  — full captured act output
run_case() {
  local case_name="$1" fixtures_src="$2"
  local work
  work="$(mktemp -d)"

  # Copy the project under test into the isolated repo.
  cp "$REPO_ROOT/aggregate.sh" "$work/"
  mkdir -p "$work/.github/workflows"
  cp "$REPO_ROOT/.github/workflows/test-results-aggregator.yml" "$work/.github/workflows/"
  # Provide the runner image selection used by this benchmark environment.
  [ -f "$REPO_ROOT/.actrc" ] && cp "$REPO_ROOT/.actrc" "$work/.actrc"

  # Stage this case's test result files as the workflow's RESULTS_DIR (fixtures).
  mkdir -p "$work/fixtures"
  cp "$fixtures_src"/* "$work/fixtures/"

  (
    cd "$work" || exit 1
    git init -q
    git config user.email ci@example.com
    git config user.name CI
    git add -A
    git commit -qm "act case: $case_name"
  )

  local out rc
  out="$(cd "$work" && act push --rm --pull=false -P "ubuntu-latest=${ACT_IMAGE}" 2>&1)"
  rc=$?

  # Append to the required artifact, clearly delimited.
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

# assert_jobs_succeeded — both jobs (aggregate, report) must report success.
assert_jobs_succeeded() {
  # act prints "Job succeeded" per successful job.
  local n
  n="$(printf '%s\n' "$ACT_OUTPUT" | grep -c 'Job succeeded' || true)"
  [ "$n" -ge 2 ] || {
    echo "expected >=2 'Job succeeded', got $n"
    return 1
  }
}

@test "act case A: full matrix aggregates to exact known totals" {
  run_case "A-full-matrix" "$REPO_ROOT/fixtures"

  # 1. act must exit 0.
  [ "$ACT_RC" -eq 0 ]

  # 2. Every job succeeded.
  assert_jobs_succeeded

  # 3. Exact aggregated metrics from the workflow's machine-greppable line.
  [[ "$ACT_OUTPUT" == *"AGGREGATE_RESULT passed=9 failed=4 skipped=2 total=15 flaky=2"* ]]

  # 4. The dependent report job propagated the same totals.
  [[ "$ACT_OUTPUT" == *"FINAL_REPORT passed=9 failed=4 skipped=2 total=15 flaky=2"* ]]

  # 5. The rendered Markdown report named exactly the two flaky tests.
  [[ "$ACT_OUTPUT" == *'`math.test_subtract`'* ]]
  [[ "$ACT_OUTPUT" == *'`net.test_connect`'* ]]
  [[ "$ACT_OUTPUT" == *"Result:** FAILED"* ]]
}

@test "act case B: alternate fixtures aggregate to their exact totals" {
  run_case "B-alternate" "$REPO_ROOT/fixtures-cases/caseB"

  [ "$ACT_RC" -eq 0 ]
  assert_jobs_succeeded

  [[ "$ACT_OUTPUT" == *"AGGREGATE_RESULT passed=3 failed=1 skipped=0 total=4 flaky=1"* ]]
  [[ "$ACT_OUTPUT" == *"FINAL_REPORT passed=3 failed=1 skipped=0 total=4 flaky=1"* ]]
  [[ "$ACT_OUTPUT" == *'`alpha.t2`'* ]]
}

@test "act-result.txt artifact exists and contains both cases" {
  [ -f "$ACT_RESULT" ]
  grep -q "ACT CASE: A-full-matrix" "$ACT_RESULT"
  grep -q "ACT CASE: B-alternate" "$ACT_RESULT"
}
