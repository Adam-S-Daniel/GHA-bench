#!/usr/bin/env bash
#
# tests/run_act_pipeline.sh
#
# Mandatory workflow-execution harness: builds a throwaway git repo containing
# this project's files, runs the real GitHub Actions workflow locally in
# Docker via `act push --rm`, and appends the captured output to
# act-result.txt (in the directory this script is invoked from), clearly
# delimited so multiple runs can be told apart.
#
# This is intentionally a plain script rather than a bats @test: invoking
# Docker/act on every `bats` run would make the everyday test suite slow and
# network-dependent. Run this script explicitly to (re)generate act-result.txt;
# tests/workflow_pipeline.bats then asserts on the artifact it produces.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result_file="${project_root}/act-result.txt"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "Setting up a throwaway git repo in $work_dir ..."
cp -r "$project_root"/secret-rotation-validator.sh \
      "$project_root"/fixtures \
      "$project_root"/secrets-config.json \
      "$project_root"/tests \
      "$project_root"/.github \
      "$project_root"/.actrc \
      "$work_dir"/

(
  cd "$work_dir"
  git init -q
  git config user.email "ci-test@example.com"
  git config user.name "CI Test Harness"
  git add -A
  git commit -q -m "test commit for act push"
)

echo "Running: act push --rm"
set +e
act_output="$(cd "$work_dir" && act push --rm 2>&1)"
act_status=$?
set -e

{
  echo "==================================================================="
  echo "Test case: full workflow pipeline (lint -> test -> notify jobs)"
  echo "Command:   act push --rm"
  echo "Fixtures exercised: secrets-config.json (production, expect all-ok),"
  echo "                    fixtures/secrets-mixed.json (demo, non-blocking),"
  echo "                    fixtures/secrets-all-expired.json (demo, non-blocking)"
  echo "==================================================================="
  echo "$act_output"
  echo "==================================================================="
  echo "act exit code: $act_status"
  echo "==================================================================="
} >> "$result_file"

echo "Saved act output to $result_file (exit code $act_status)"
exit "$act_status"
