#!/usr/bin/env bash
# run-act-harness.sh -- build an isolated temp git repo containing a
# snapshot of this project, run the GitHub Actions workflow locally via
# `act push --rm`, and save the full output to act-result.txt in the
# project's working directory.
#
# This is the ONLY place `act` is invoked. test/act_pipeline.bats calls
# this once (from setup_file, so it runs a single time for the whole
# bats file) and then makes all of its assertions by reading the saved
# act-result.txt -- per project policy, functional behavior is verified
# through the real GitHub Actions pipeline, not by calling
# aggregate-results.sh directly.

set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${PROJECT_DIR}/act-result.txt"

# Script-global (not a `local` inside main) so the EXIT trap -- which
# fires after main() has already returned -- can still see it.
TMP_REPO=""
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap below
cleanup() { [[ -n "$TMP_REPO" ]] && rm -rf "$TMP_REPO"; }
trap cleanup EXIT

main() {
  if ! command -v act >/dev/null 2>&1; then
    echo "ERROR: 'act' is not installed or not on PATH" >&2
    return 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: 'docker' is not installed or not on PATH" >&2
    return 1
  fi

  TMP_REPO="$(mktemp -d)"
  local tmp_repo="$TMP_REPO"

  # Snapshot the project (script, lib, fixtures, workflow, .actrc) into
  # the temp repo. Exclude the outer .git (this project directory is
  # itself checked out inside a larger repo) and any previous
  # act-result.txt so the temp repo only contains what the workflow
  # actually needs.
  cp -R "${PROJECT_DIR}/." "$tmp_repo/"
  rm -rf "${tmp_repo:?}/.git" "${tmp_repo}/act-result.txt"

  {
    echo "===== ACT PUSH RUN ====="
    echo "scenarios: basic-matrix-aggregation, empty-results, malformed-xml-rejected, invalid-json-rejected, unsupported-extension-rejected"
    echo "========================="
  } > "$OUTPUT_FILE"

  (
    cd "$tmp_repo" || exit 1
    git init -q
    git config user.email "act-harness@example.com"
    git config user.name "act-harness"
    git add -A
    git commit -q -m "test: act harness snapshot"
    # --pull=false: the ubuntu-latest image (act-ubuntu-pwsh:latest, see
    # .actrc) is a locally-built image with no matching remote registry
    # entry: act's default force-pull would fail authentication trying
    # to pull it, so we must tell it to use the local image as-is.
    act push --rm --pull=false
  ) >> "$OUTPUT_FILE" 2>&1
  local act_exit=$?

  echo "===== act exited with status ${act_exit} =====" >> "$OUTPUT_FILE"
  return "$act_exit"
}

main "$@"
exit $?
