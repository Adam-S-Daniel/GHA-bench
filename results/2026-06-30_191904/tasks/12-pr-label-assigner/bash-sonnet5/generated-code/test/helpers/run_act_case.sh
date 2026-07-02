#!/usr/bin/env bash
#
# run_act_case.sh REPO_ROOT CHANGED_FILES_FIXTURE
#
# Sets up an isolated temp git repo containing the project's script,
# rules, workflow, and fixtures, overwrites fixtures/changed-files.txt
# with CHANGED_FILES_FIXTURE's content (simulating a specific PR's changed
# file list), commits it, and runs the pr-label-assigner workflow via
# `act push --rm`. Prints act's combined stdout/stderr and exits with
# act's exit code, so callers can use `run` on this script directly.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: run_act_case.sh REPO_ROOT CHANGED_FILES_FIXTURE" >&2
  exit 2
fi

repo_root="$1"
fixture="$2"

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

cp "$repo_root/label-assigner.sh" "$workdir/"
cp "$repo_root/rules.conf" "$workdir/"
cp "$repo_root/.actrc" "$workdir/"
cp -r "$repo_root/.github" "$workdir/"
cp -r "$repo_root/fixtures" "$workdir/"
cp "$fixture" "$workdir/fixtures/changed-files.txt"

cd "$workdir"
git init -q
git config user.email "test@example.com"
git config user.name "PR Label Assigner Test"
git add -A
git commit -q -m "test case: $(basename "$fixture")"

act push --rm 2>&1
