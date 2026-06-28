#!/usr/bin/env bash
# Shared helpers for the bats test suite.
#
# Every test file `load`s this helper. It exposes absolute paths to the
# deliverables so individual tests do not depend on the current working
# directory, and provides the act-integration plumbing used by act.bats.

# Absolute path to the project root (the parent of this tests/ directory).
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# The deliverables under test.
SCRIPT="${PROJECT_ROOT}/aggregate-test-results.sh"
WORKFLOW="${PROJECT_ROOT}/.github/workflows/test-results-aggregator.yml"
export SCRIPT WORKFLOW

# The required act artifact. Every act scenario appends its output here.
ACT_RESULT="${PROJECT_ROOT}/act-result.txt"
export ACT_RESULT

# prepare_repo <scenario> — build a throwaway git repo in a temp dir that
# contains the project files plus the scenario's fixture data under fixtures/.
# Sets the global REPO to the temp dir path. The caller is responsible for
# running act inside REPO and for cleanup.
prepare_repo() {
  local scenario="$1"
  local src="${PROJECT_ROOT}/tests/scenarios/${scenario}"
  [ -d "$src" ] || { echo "unknown scenario: ${scenario}" >&2; return 1; }

  REPO="$(mktemp -d)"
  export REPO

  # Copy the project artifacts the workflow needs.
  cp "${SCRIPT}" "${REPO}/aggregate-test-results.sh"
  mkdir -p "${REPO}/.github/workflows"
  cp "${WORKFLOW}" "${REPO}/.github/workflows/test-results-aggregator.yml"
  # Carry the act runner config (image mapping) into the temp repo so act
  # resolves ubuntu-latest to the locally-built image instead of pulling.
  [ -f "${PROJECT_ROOT}/.actrc" ] && cp "${PROJECT_ROOT}/.actrc" "${REPO}/.actrc"

  # Stage this scenario's test result files as the fixtures/ the workflow reads.
  mkdir -p "${REPO}/fixtures"
  cp "${src}/." "${REPO}/fixtures/" -r

  (
    cd "${REPO}" || exit 1
    git init -q
    git config user.email "tester@example.com"
    git config user.name "tester"
    git add -A
    git commit -q -m "scenario ${scenario}"
  )
}

# append_act_log <scenario> <exit-code> <output> — append a clearly delimited
# record of one act run to the required act-result.txt artifact.
append_act_log() {
  local scenario="$1" code="$2" output="$3"
  {
    echo "######################################################################"
    echo "### ACT SCENARIO: ${scenario}   (act exit code: ${code})"
    echo "######################################################################"
    printf '%s\n\n' "$output"
  } >> "${ACT_RESULT}"
}
