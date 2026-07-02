#!/usr/bin/env bats
# Integration tests: the workflow is executed exactly once, for real, via
# `act push`, in an isolated temp git repo. Every test case below (one per
# fixture) is exercised in that single run because the workflow's
# "generate-matrix" job fans out over all three fixtures as a job matrix,
# and the "generate"/"build"/"validate-size-limit" jobs run alongside it.
# We do NOT test matrix-generator.sh directly -- all assertions below are
# parsed out of the captured `act` output, i.e. the real pipeline run.
#
# This keeps us to a single `act push` invocation (well under the 3-run
# budget) while still routing every test case through the real workflow.

setup_file() {
  local project_dir
  project_dir="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  local work
  work="$(mktemp -d)"

  cp -r "$project_dir/matrix-generator.sh" "$work/"
  cp -r "$project_dir/fixtures" "$work/"
  cp -r "$project_dir/.github" "$work/"
  cp -r "$project_dir/.actrc" "$work/"

  (
    # Disable bats' inherited `set -e` / ERR trap here: act push is expected
    # to exit non-zero as a whole in some scenarios, but we want to capture
    # its output and real exit code ourselves rather than aborting.
    set +e
    trap - ERR
    cd "$work" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    git add -A
    git commit -q -m "test fixture commit"
    # --pull=false: the benchmark's act image is already present locally;
    # act's default force-pull attempts a registry auth handshake that
    # fails in this sandboxed environment even though the image exists.
    act push --rm --pull=false > act_output.txt 2>&1
    echo "$?" > act_exit_code.txt
    exit 0
  )

  {
    echo "===== act push run: $(date -u +%FT%TZ 2>/dev/null || echo unknown) ====="
    cat "$work/act_output.txt"
    echo "===== end act push run (exit code: $(cat "$work/act_exit_code.txt")) ====="
  } >> "$project_dir/act-result.txt"

  echo "$work/act_output.txt" > "$BATS_FILE_TMPDIR/act_output_path"
  echo "$work/act_exit_code.txt" > "$BATS_FILE_TMPDIR/act_exit_path"
}

act_output() {
  cat "$(cat "$BATS_FILE_TMPDIR/act_output_path")"
}

act_exit_code() {
  cat "$(cat "$BATS_FILE_TMPDIR/act_exit_path")"
}

# act prefixes every output line with "[<workflow>/<job name w/ matrix>]",
# so a line containing both the job-name prefix and "Job succeeded" can only
# belong to that specific job -- it cannot match a different job's success.
job_succeeded() {
  local job_name_fragment="$1"
  act_output | grep -F "/${job_name_fragment}" | grep -q "Job succeeded"
}

@test "act-result.txt artifact was created" {
  [ -f "$BATS_TEST_DIRNAME/../act-result.txt" ]
}

@test "act push exited 0 (all jobs succeeded)" {
  [ "$(act_exit_code)" = "0" ]
}

@test "job succeeded: Generate canonical matrix" {
  run job_succeeded "Generate canonical matrix"
  [ "$status" -eq 0 ]
}

@test "job succeeded: build (basic matrix consumption)" {
  run job_succeeded "Build ("
  [ "$status" -eq 0 ]
}

@test "job succeeded: Validate max-size enforcement" {
  run job_succeeded "Validate max-size enforcement"
  [ "$status" -eq 0 ]
}

@test "job succeeded: Generate matrix (basic)" {
  run job_succeeded "Generate matrix (basic)"
  [ "$status" -eq 0 ]
}

@test "job succeeded: Generate matrix (exclude_flags_include)" {
  run job_succeeded "Generate matrix (exclude_flags_include)"
  [ "$status" -eq 0 ]
}

@test "job succeeded: Generate matrix (minimal_defaults)" {
  run job_succeeded "Generate matrix (minimal_defaults)"
  [ "$status" -eq 0 ]
}

@test "fixture 'basic': exact expected matrix JSON is produced" {
  run act_output
  expected='{"matrix":{"include":[{"os":"ubuntu-latest","version":"18"},{"os":"ubuntu-latest","version":"20"},{"os":"windows-latest","version":"18"},{"os":"windows-latest","version":"20"}]},"fail-fast":true,"max-parallel":4}'
  [[ "$output" == *"$expected"* ]]
}

@test "fixture 'exclude_flags_include': exact expected matrix JSON is produced" {
  run act_output
  expected='{"matrix":{"include":[{"os":"ubuntu-latest","version":"18","arch":"x64","canary":true},{"os":"ubuntu-latest","version":"18","arch":"arm64"},{"os":"ubuntu-latest","version":"20","arch":"x64"},{"os":"ubuntu-latest","version":"20","arch":"arm64"},{"os":"windows-latest","version":"20","arch":"x64"},{"os":"windows-latest","version":"20","arch":"arm64"},{"os":"macos-latest","version":"18","arch":"arm64"},{"os":"macos-latest","version":"20","arch":"arm64"},{"os":"ubuntu-latest","version":"22","arch":"x64","experimental":true}]},"fail-fast":false}'
  [[ "$output" == *"$expected"* ]]
}

@test "fixture 'minimal_defaults': exact expected matrix JSON is produced (defaults applied)" {
  run act_output
  expected='{"matrix":{"include":[{"os":"ubuntu-latest","version":"16"},{"os":"ubuntu-latest","version":"18"},{"os":"ubuntu-latest","version":"20"}]},"fail-fast":true}'
  [[ "$output" == *"$expected"* ]]
}

@test "fixture 'too_big': size-limit violation is correctly rejected with exact message" {
  run act_output
  [[ "$output" == *"Error: generated matrix size (9) exceeds max-size (5)"* ]]
  [[ "$output" == *"Correctly rejected oversized matrix"* ]]
}
