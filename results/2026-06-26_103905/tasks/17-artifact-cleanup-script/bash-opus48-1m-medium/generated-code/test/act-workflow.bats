#!/usr/bin/env bats
#
# Integration tests: every assertion below is made against output produced by
# running the real GitHub Actions workflow through `act` (nektos/act). The
# script is never invoked directly here.
#
# Strategy (per the task spec):
#   * For each case, build a throwaway git repo containing the project files
#     plus that case's fixture data.
#   * Run `act push --rm`, capture the output, and append it to act-result.txt.
#   * Assert act exited 0, that both jobs report "Job succeeded", and that the
#     plan summary matches the exact known-good numbers for that fixture.

setup_file() {
  PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_DIR
  ACT_RESULT="${PROJECT_DIR}/act-result.txt"
  export ACT_RESULT
  # Start each run with a fresh aggregate log.
  : > "${ACT_RESULT}"
}

# run_case <label> <fixture-source-file>
# Builds an isolated git repo, swaps in the fixture, runs act, records output.
run_case() {
  local label="$1" fixture_src="$2"
  local work
  work="$(mktemp -d)"

  # Copy the project files the workflow needs into the throwaway repo.
  cp "${PROJECT_DIR}/artifact-cleanup.sh" "${work}/"
  cp "${PROJECT_DIR}/.actrc" "${work}/" 2>/dev/null || true
  mkdir -p "${work}/fixtures" "${work}/.github/workflows"
  cp "${PROJECT_DIR}/.github/workflows/artifact-cleanup-script.yml" "${work}/.github/workflows/"
  # This case's fixture data becomes the inventory the workflow reads.
  cp "${fixture_src}" "${work}/fixtures/artifacts.tsv"

  # act operates on a git repo; create one with a single commit.
  git -C "${work}" init -q
  git -C "${work}" config user.email ci@example.com
  git -C "${work}" config user.name CI
  git -C "${work}" add -A
  git -C "${work}" commit -q -m "case ${label}"

  # Run the workflow. -P pins the container image; --pull=false uses the
  # locally-built image instead of trying to pull it from a registry. The `if`
  # captures act's real exit status without letting a non-zero abort the helper
  # before we persist the output below.
  local out_file="${work}/act.out"
  if (cd "${work}" && act push --rm \
        -P ubuntu-latest=act-ubuntu-pwsh:latest \
        --pull=false \
        -W .github/workflows/artifact-cleanup-script.yml) > "${out_file}" 2>&1
  then
    ACT_STATUS=0
  else
    ACT_STATUS=$?
  fi
  ACT_OUTPUT="$(cat "${out_file}")"

  # Persist the full output, clearly delimited, as the required artifact.
  {
    echo "===================================================================="
    echo "ACT CASE: ${label} (exit=${ACT_STATUS})"
    echo "===================================================================="
    echo "${ACT_OUTPUT}"
    echo ""
  } >> "${ACT_RESULT}"

  rm -rf "${work}"
}

# --- Case 1: the committed default fixture -----------------------------------
# Expected (computed by hand and verified against the script):
#   build-logs  -> max-age (57 days old, > 30)
#   docs        -> keep-latest (run 200 keeps the 2 newest: dist, test-results)
#   test-results-> max-size (kept total 6500 > 6000, drop oldest kept)
#   => total=5 retained=2 deleted=3 reclaimed=3000
@test "act: default fixture yields the exact expected deletion plan" {
  run_case "default" "${PROJECT_DIR}/fixtures/artifacts.tsv"

  [ "${ACT_STATUS}" -eq 0 ]
  # Both jobs must complete successfully.
  [ "$(grep -c 'Job succeeded' <<< "${ACT_OUTPUT}")" -ge 2 ]
  # Exact summary numbers.
  [[ "${ACT_OUTPUT}" == *"Total artifacts: 5"* ]]
  [[ "${ACT_OUTPUT}" == *"Retained: 2"* ]]
  [[ "${ACT_OUTPUT}" == *"Deleted: 3"* ]]
  [[ "${ACT_OUTPUT}" == *"Space reclaimed: 3000 bytes (2.9 KB)"* ]]
  # The aggregated report job echoes the parsed outputs.
  [[ "${ACT_OUTPUT}" == *"PLAN_RESULT total=5 retained=2 deleted=3 reclaimed=3000"* ]]
}

# --- Case 2: a fixture under all the limits (nothing deleted) -----------------
# Two small, recent artifacts in one run: no policy selects anything.
#   => total=2 retained=2 deleted=0 reclaimed=0
@test "act: under-limit fixture deletes nothing" {
  local f="${BATS_TEST_TMPDIR}/small.tsv"
  printf '%s\t%s\t%s\t%s\n' \
    "alpha" 100 "2026-06-26T00:00:00Z" 1 \
    "beta"  200 "2026-06-25T00:00:00Z" 1 \
    > "${f}"

  run_case "under-limit" "${f}"

  [ "${ACT_STATUS}" -eq 0 ]
  [ "$(grep -c 'Job succeeded' <<< "${ACT_OUTPUT}")" -ge 2 ]
  [[ "${ACT_OUTPUT}" == *"Total artifacts: 2"* ]]
  [[ "${ACT_OUTPUT}" == *"Retained: 2"* ]]
  [[ "${ACT_OUTPUT}" == *"Deleted: 0"* ]]
  [[ "${ACT_OUTPUT}" == *"Space reclaimed: 0 bytes"* ]]
  [[ "${ACT_OUTPUT}" == *"PLAN_RESULT total=2 retained=2 deleted=0 reclaimed=0"* ]]
}

# --- Structural checks on the workflow itself (no act run) --------------------

@test "workflow: actionlint passes cleanly" {
  run actionlint "${PROJECT_DIR}/.github/workflows/artifact-cleanup-script.yml"
  [ "$status" -eq 0 ]
}

@test "workflow: references the script and fixture that actually exist" {
  local wf="${PROJECT_DIR}/.github/workflows/artifact-cleanup-script.yml"
  grep -q 'artifact-cleanup.sh' "$wf"
  grep -q 'fixtures/artifacts.tsv' "$wf"
  [ -f "${PROJECT_DIR}/artifact-cleanup.sh" ]
  [ -f "${PROJECT_DIR}/fixtures/artifacts.tsv" ]
}

@test "workflow: declares expected triggers, jobs, dependency and permissions" {
  local wf="${PROJECT_DIR}/.github/workflows/artifact-cleanup-script.yml"
  grep -q 'actions/checkout@v4' "$wf"
  grep -qE '^\s*push:' "$wf"
  grep -qE '^\s*pull_request:' "$wf"
  grep -qE '^\s*schedule:' "$wf"
  grep -qE '^\s*workflow_dispatch:' "$wf"
  grep -qE '^\s*permissions:' "$wf"
  grep -qE '^\s*plan:' "$wf"
  grep -qE '^\s*report:' "$wf"
  grep -qE '^\s*needs:\s*plan' "$wf"
}
