#!/usr/bin/env bats
#
# Pipeline integration tests. Every behavioural assertion here is made against
# output produced by running the GitHub Actions workflow through `act` — the
# script is never executed directly in this file.
#
# The workflow's driver (ci/run-cases.sh) iterates over all fixture cases in a
# single run, so one `act push` invocation exercises every test case. Its full
# output is captured to act-result.txt (a required artifact), and each @test
# asserts the exact known-good values for one case.

# Resolve the project root and key paths.
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
ACT_RESULT="${PROJECT_ROOT}/act-result.txt"
WORKFLOW="${PROJECT_ROOT}/.github/workflows/artifact-cleanup-script.yml"
ACT_EXIT_FILE="${BATS_FILE_TMPDIR:-/tmp}/act.exit"

# ---------------------------------------------------------------------------
# setup_file runs once for the whole file: it builds an isolated git repo from
# the project files + fixtures and runs `act push` a single time, capturing all
# output to act-result.txt.
# ---------------------------------------------------------------------------
setup_file() {
  export PROJECT_ROOT ACT_RESULT ACT_EXIT_FILE

  local workdir
  workdir="$(mktemp -d)"
  export ACT_WORKDIR="${workdir}"

  # Copy exactly the files the workflow needs into the throwaway repo.
  cp "${PROJECT_ROOT}/artifact-cleanup.sh" "${workdir}/"
  cp "${PROJECT_ROOT}/.actrc" "${workdir}/"
  cp -r "${PROJECT_ROOT}/ci" "${workdir}/"
  cp -r "${PROJECT_ROOT}/ci-fixtures" "${workdir}/"
  cp -r "${PROJECT_ROOT}/.github" "${workdir}/"

  # act only sees committed files for a `push` event, so make a real commit.
  (
    cd "${workdir}"
    git init -q
    git config user.email "ci@example.com"
    git config user.name "ci"
    git add -A
    git commit -qm "fixture repo for act"
  )

  # Run the pipeline once. --rm cleans the container; --pull=false uses the
  # locally-built act image referenced by .actrc.
  {
    echo "===== ACT RUN: push event (all fixture cases) ====="
    echo "# repo: ${workdir}"
  } > "${ACT_RESULT}"

  local rc=0
  ( cd "${workdir}" && act push --rm --pull=false ) >> "${ACT_RESULT}" 2>&1 || rc=$?
  echo "${rc}" > "${ACT_EXIT_FILE}"

  {
    echo "===== ACT EXIT CODE: ${rc} ====="
  } >> "${ACT_RESULT}"
}

teardown_file() {
  rm -rf "${ACT_WORKDIR:-}"
}

# Helper: read the captured act exit code.
act_exit_code() {
  cat "${ACT_EXIT_FILE}"
}

@test "act push exited with code 0" {
  [ -f "${ACT_EXIT_FILE}" ]
  run act_exit_code
  [ "${output}" = "0" ]
}

@test "act-result.txt artifact was produced and is non-empty" {
  [ -s "${ACT_RESULT}" ]
}

@test "both jobs report Job succeeded" {
  run grep -c "Job succeeded" "${ACT_RESULT}"
  [ "${status}" -eq 0 ]
  # The workflow has two jobs: lint and cleanup-plan.
  [ "${output}" -ge 2 ]
}

@test "lint job ran and bash -n passed" {
  run grep -q "bash -n passed for both scripts" "${ACT_RESULT}"
  [ "${status}" -eq 0 ]
}

@test "case1-combined: exact combined-policy plan via the pipeline" {
  grep -q "===== CASE case1-combined =====" "${ACT_RESULT}"
  grep -q "Artifact Cleanup Plan (DRY RUN)" "${ACT_RESULT}"
  grep -q "DELETE a-old size=5000 run=100 reason=age+keep-latest" "${ACT_RESULT}"
  grep -q "DELETE b-keep1 size=5000 run=100 reason=keep-latest" "${ACT_RESULT}"
  grep -q "DELETE b-keep2 size=5000 run=100 reason=max-size" "${ACT_RESULT}"
  grep -q "KEEP c-run200 size=9000 run=200" "${ACT_RESULT}"
  grep -q "SUMMARY total=4 retained=1 deleted=3 reclaimed_bytes=15000" "${ACT_RESULT}"
}

@test "case2-age: exact max-age plan via the pipeline" {
  grep -q "===== CASE case2-age =====" "${ACT_RESULT}"
  grep -q "Artifact Cleanup Plan (LIVE)" "${ACT_RESULT}"
  grep -q "DELETE stale size=1000 run=10 reason=age" "${ACT_RESULT}"
  grep -q "KEEP recent size=2000 run=10" "${ACT_RESULT}"
  grep -q "SUMMARY total=2 retained=1 deleted=1 reclaimed_bytes=1000" "${ACT_RESULT}"
}

@test "case3-keep-latest: exact keep-latest plan via the pipeline" {
  grep -q "===== CASE case3-keep-latest =====" "${ACT_RESULT}"
  grep -q "DELETE v1 size=100 run=5 reason=keep-latest" "${ACT_RESULT}"
  grep -q "KEEP v2 size=200 run=5" "${ACT_RESULT}"
  grep -q "KEEP v3 size=300 run=5" "${ACT_RESULT}"
  grep -q "SUMMARY total=3 retained=2 deleted=1 reclaimed_bytes=100" "${ACT_RESULT}"
}

@test "workflow's own verification step passed inside the pipeline" {
  run grep -q "All fixture plans verified." "${ACT_RESULT}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Workflow structure tests — fast, do not depend on the act run.
# ---------------------------------------------------------------------------

@test "actionlint validates the workflow cleanly" {
  run actionlint "${WORKFLOW}"
  [ "${status}" -eq 0 ]
}

@test "workflow declares the expected triggers" {
  grep -qE "^\s*push:" "${WORKFLOW}"
  grep -qE "^\s*pull_request:" "${WORKFLOW}"
  grep -qE "^\s*schedule:" "${WORKFLOW}"
  grep -qE "^\s*workflow_dispatch:" "${WORKFLOW}"
}

@test "workflow defines lint and cleanup-plan jobs with a dependency" {
  grep -qE "^\s+lint:" "${WORKFLOW}"
  grep -qE "^\s+cleanup-plan:" "${WORKFLOW}"
  grep -qE "needs:\s*lint" "${WORKFLOW}"
}

@test "workflow references scripts that actually exist" {
  grep -q "artifact-cleanup.sh" "${WORKFLOW}"
  grep -q "ci/run-cases.sh" "${WORKFLOW}"
  [ -f "${PROJECT_ROOT}/artifact-cleanup.sh" ]
  [ -f "${PROJECT_ROOT}/ci/run-cases.sh" ]
}

@test "workflow declares least-privilege permissions" {
  grep -qE "contents:\s*read" "${WORKFLOW}"
}
