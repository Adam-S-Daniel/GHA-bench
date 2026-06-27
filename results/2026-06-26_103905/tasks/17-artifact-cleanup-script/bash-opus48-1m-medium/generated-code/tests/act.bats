#!/usr/bin/env bats
#
# End-to-end act harness. EVERY assertion here is made on output produced by
# running the workflow through `act` (nektos/act) inside Docker — the script is
# never invoked directly.
#
# For each test case we:
#   1. build a throwaway git repo containing the project files plus that case's
#      fixture data (fixtures/artifacts.tsv + fixtures/policy.env),
#   2. run `act push --rm` against it,
#   3. append the full act output to act-result.txt (clearly delimited),
#   4. assert act exited 0, every job reports "Job succeeded", and the deletion
#      plan contains the EXACT expected values for that case's input.
#
# The fixture is identical across cases (NOW = 1782432000 = 2026-06-26T00:00Z):
#   a  size=100  created=1781568000  run=1   (10 days old)
#   b  size=200  created=1782000000  run=1   ( 5 days old)
#   c  size=300  created=1778976000  run=2   (40 days old)
# Only the retention policy (policy.env) changes per case, so each expected
# result is hand-computable and pinned below.

# Truncate the shared result file exactly once, before any test runs.
# (Exported vars from setup_file are not reliably visible in test bodies, so we
# recompute the path here and again in setup().)
setup_file() {
  : > "$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/act-result.txt"
}

# Per-test: set the paths used by every helper. Runs in the test's own process,
# so these are guaranteed visible (unlike setup_file exports).
setup() {
  PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  ACT_RESULT="${PROJECT_DIR}/act-result.txt"
}

# act derives deterministic container/volume names from the workflow name, so
# consecutive runs collide ("volume is in use" / "No such container"). Force
# remove any leftovers from a previous case before starting the next one.
clean_act_state() {
  docker ps -aq --filter "name=act-Artifact-Cleanup" \
    | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker volume ls -q --filter "name=act-Artifact-Cleanup" \
    | xargs -r docker volume rm -f >/dev/null 2>&1 || true
}

# run_case NAME POLICY_ENV_CONTENT
# Builds an isolated git repo, runs the workflow through act, and records the
# output. Leaves the act exit status in $status and output in $output (via the
# bats `run` wrapper in each test).
build_repo() {
  clean_act_state
  local policy="$1"
  REPO="$(mktemp -d)"
  # Copy the project files act needs: script, tests, fixtures, workflow, actrc.
  cp "${PROJECT_DIR}/artifact-cleanup.sh" "$REPO/"
  cp "${PROJECT_DIR}/.actrc" "$REPO/" 2>/dev/null || true
  mkdir -p "$REPO/tests" "$REPO/fixtures" "$REPO/.github/workflows"
  cp "${PROJECT_DIR}/tests/cleanup.bats" "$REPO/tests/"
  cp "${PROJECT_DIR}/fixtures/artifacts.tsv" "$REPO/fixtures/"
  cp "${PROJECT_DIR}/.github/workflows/artifact-cleanup-script.yml" \
     "$REPO/.github/workflows/"
  # Per-case policy.
  printf '%s\n' "$policy" > "$REPO/fixtures/policy.env"
  # act requires a git repository with at least one commit.
  git -C "$REPO" init -q
  git -C "$REPO" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$REPO" -c user.email=ci@example.com -c user.name=ci \
      commit -q -m "test case"
}

# run_act — run the workflow through act, retrying ONLY on known Docker daemon
# transients seen under WSL2 with a heavily-shared daemon (overlay RWLayer
# races, "No such container" mid-copy, stuck named volumes). Sets bats-style
# $status and $output. A genuine workflow failure (no transient marker) is
# returned immediately, never masked.
#
# Flags:
#   --pull=false : the act image is local-only, so never try to pull it.
#   --bind       : bind-mount the repo instead of `docker cp`-ing it into a
#                  named volume; this sidesteps the flaky copy/volume-reuse step
#                  that fails under daemon contention.
#   --rm         : remove job containers when done (required by the task).
run_act() {
  local attempt=0 max=8 rc
  local transient='RWLayer of container|unexpectedly nil|No such container|volume is in use|failed to copy content to container|error during connect'
  while : ; do
    attempt=$((attempt + 1))
    clean_act_state
    # `if` wrapper captures the exit code without tripping bats' errexit, which
    # would otherwise abort run_act on the first non-zero act run.
    if output="$(act push --rm --pull=false --bind 2>&1)"; then
      rc=0
    else
      rc=$?
    fi
    status=$rc
    [ "$rc" -eq 0 ] && return 0
    if [ "$attempt" -ge "$max" ]; then return "$rc"; fi
    if grep -qE "$transient" <<< "$output"; then
      continue   # transient docker error -> clean and retry
    fi
    return "$rc"  # real failure -> surface immediately
  done
}

# record CASE_NAME — append the current $output to act-result.txt, delimited.
record() {
  {
    echo "################################################################"
    echo "# ACT CASE: $1"
    echo "# exit status: $status"
    echo "################################################################"
    echo "$output"
    echo ""
  } >> "$ACT_RESULT"
}

# Every job in the workflow must report success.
assert_all_jobs_succeeded() {
  # validate, test, plan -> three "Job succeeded" lines.
  local count
  count="$(grep -c "Job succeeded" <<< "$output" || true)"
  [ "$count" -eq 3 ]
}

@test "act case A: max-age-days 30 deletes the 40-day-old artifact" {
  build_repo $'MAX_AGE_DAYS=30\nKEEP_LATEST=\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=0'
  cd "$REPO"
  run_act || true
  record "A: max-age-days 30"
  [ "$status" -eq 0 ]
  assert_all_jobs_succeeded
  # c (40d old) is deleted by max-age; a and b survive.
  [[ "$output" == *"DELETE"*"c"*"max-age"* ]]
  [[ "$output" == *"Total artifacts: 3"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 300 bytes"* ]]
  rm -rf "$REPO"
}

@test "act case B: keep-latest 1 keeps newest per run, deletes the older one" {
  build_repo $'MAX_AGE_DAYS=\nKEEP_LATEST=1\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=0'
  cd "$REPO"
  run_act || true
  record "B: keep-latest 1"
  [ "$status" -eq 0 ]
  assert_all_jobs_succeeded
  # run 1: b newer than a -> a deleted; run 2: c alone -> kept.
  [[ "$output" == *"DELETE"*"a"*"keep-latest"* ]]
  [[ "$output" == *"Retained: 2"* ]]
  [[ "$output" == *"Deleted: 1"* ]]
  [[ "$output" == *"Space reclaimed: 100 bytes"* ]]
  rm -rf "$REPO"
}

@test "act case C: combined age+keep-latest dry-run deletes two, keeps one" {
  build_repo $'MAX_AGE_DAYS=30\nKEEP_LATEST=1\nMAX_TOTAL_SIZE=\nNOW=1782432000\nDRY_RUN=1'
  cd "$REPO"
  run_act || true
  record "C: max-age 30 + keep-latest 1 + dry-run"
  [ "$status" -eq 0 ]
  assert_all_jobs_succeeded
  # age>30 deletes c; keep-latest 1 deletes a; b survives. Plan marked dry-run.
  [[ "$output" == *"DRY-RUN"* ]]
  [[ "$output" == *"Retained: 1"* ]]
  [[ "$output" == *"Deleted: 2"* ]]
  [[ "$output" == *"Space reclaimed: 400 bytes"* ]]
  rm -rf "$REPO"
}
