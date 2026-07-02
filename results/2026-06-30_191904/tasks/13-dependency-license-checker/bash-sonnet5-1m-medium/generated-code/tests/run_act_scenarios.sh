#!/usr/bin/env bash
# run_act_scenarios.sh
#
# Drives the GitHub Actions workflow through `act` for several test-case
# fixture manifests, each in its own throwaway temp git repo, and appends
# all act output to act-result.txt (in the project root) so results are
# verifiable after the fact. Per the benchmark harness requirements, no
# script logic is tested directly -- everything goes through the pipeline.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="${PROJECT_ROOT}/act-result.txt"

: > "$RESULT_FILE"  # truncate/create

# copy_project_into <dest-dir>
# Copies everything act/the workflow needs (script, lib, fixtures, workflow,
# tests, .actrc) into a fresh directory that will become a temp git repo.
copy_project_into() {
  local dest="$1"
  mkdir -p "$dest"
  cp -R "${PROJECT_ROOT}/.github" "$dest/"
  cp -R "${PROJECT_ROOT}/lib" "$dest/"
  cp -R "${PROJECT_ROOT}/fixtures" "$dest/"
  cp -R "${PROJECT_ROOT}/scenario" "$dest/"
  cp -R "${PROJECT_ROOT}/tests" "$dest/"
  cp "${PROJECT_ROOT}/check-licenses.sh" "$dest/"
  cp "${PROJECT_ROOT}/.actrc" "$dest/"
}

# run_scenario <name> <package-json-fixture-content>
# Sets up a temp git repo with the given content swapped into
# scenario/package.json (the file the workflow's license-check job reads),
# leaving fixtures/package.json untouched for the unit-test job. Runs
# `act push --rm` and appends the labeled output to $RESULT_FILE.
run_scenario() {
  local name="$1" package_json_content="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  copy_project_into "$tmp_dir"
  echo "$package_json_content" > "${tmp_dir}/scenario/package.json"

  (
    cd "$tmp_dir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test Runner"
    git add -A
    git commit -q -m "scenario: ${name}"
  )

  {
    echo "===== TEST CASE: ${name} ====="
  } >> "$RESULT_FILE"

  local exit_code=0
  (cd "$tmp_dir" && act push --rm --pull=false) >> "$RESULT_FILE" 2>&1 || exit_code=$?

  {
    echo "EXIT_CODE: ${exit_code}"
    echo "===== END TEST CASE: ${name} ====="
    echo ""
  } >> "$RESULT_FILE"

  rm -rf "$tmp_dir"

  return "$exit_code"
}

overall_status=0

run_scenario "clean-package-json" '{
  "dependencies": {
    "left-pad": "1.3.0",
    "lodash": "4.17.21",
    "express": "4.18.2"
  },
  "devDependencies": {
    "jest": "29.7.0"
  }
}' || overall_status=$?

run_scenario "unknown-dependency" '{
  "dependencies": {
    "lodash": "4.17.21",
    "totally-unheard-of-pkg": "1.0.0"
  }
}' || overall_status=$?

exit "$overall_status"
