#!/usr/bin/env bash
#
# run-act-cases.sh — act-based integration harness for the secret rotation
# validator workflow.
#
# For each test case it:
#   1. Creates an isolated temp git repo containing the project files plus that
#      case's fixture data (copied into fixtures/secrets.json, the path the
#      workflow reads).
#   2. Runs the workflow end-to-end with `act push --rm`, capturing all output.
#   3. Appends the captured output to act-result.txt (clearly delimited) in the
#      project root, and saves a per-case copy under test/.act-out/ so the bats
#      suite can assert on exact expected values.
#   4. Asserts act exited 0 and that every job reported "Job succeeded".
#
# The workflow pins ROTATION_NOW=2024-04-01 and WARNING_DAYS=14 for `push`
# events, so each fixture's classification is fully deterministic.
#
# Run from anywhere:  bash test/run-act-cases.sh

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )"

ACT_RESULT="$PROJECT_ROOT/act-result.txt"
OUT_DIR="$PROJECT_ROOT/test/.act-out"

# Start each run with a fresh result artifact and per-case output dir.
: > "$ACT_RESULT"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Test cases: "case_name:relative_fixture_path".
# Each fixture, evaluated at now=2024-04-01 with a 14-day window, has a known
# expired/warning/ok breakdown that the bats suite asserts on.
CASES=(
  "mixed:fixtures/secrets.json"
  "all-ok:fixtures/cases/all-ok.json"
  "all-expired:fixtures/cases/all-expired.json"
)

overall_rc=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  fixture="${entry#*:}"

  echo ">>> Running act case: $name (fixture: $fixture)"

  workdir="$(mktemp -d)"
  # Best-effort cleanup of the temp repo.
  trap 'rm -rf "$workdir"' EXIT

  # Assemble the isolated project tree.
  mkdir -p "$workdir/.github/workflows" "$workdir/fixtures/cases"
  cp "$PROJECT_ROOT/secret-rotation-validator.sh" "$workdir/"
  cp "$PROJECT_ROOT/.actrc" "$workdir/"
  cp "$PROJECT_ROOT/.github/workflows/secret-rotation-validator.yml" \
     "$workdir/.github/workflows/"

  # Put this case's fixture where the workflow expects it.
  cp "$PROJECT_ROOT/$fixture" "$workdir/fixtures/secrets.json"

  # Initialise a committed git repo so actions/checkout has a ref to resolve.
  (
    cd "$workdir"
    git init -q
    git config user.email "ci@example.com"
    git config user.name "CI"
    git add -A
    git commit -q -m "act case: $name"
  )

  # Execute the workflow. Capture combined output and the exit code without
  # letting set -e abort the loop.
  out_file="$OUT_DIR/$name.txt"
  # --pull=false: the act runner image is built locally (act-ubuntu-pwsh) and
  # is not in any registry, so a forced pull would fail with an auth error.
  set +e
  ( cd "$workdir" && act push --rm --pull=false ) > "$out_file" 2>&1
  rc=$?
  set -e

  # Append a clearly delimited block to the shared artifact.
  {
    echo "==================== ACT CASE: $name ===================="
    echo "fixture: $fixture"
    echo "exit_code: $rc"
    echo "-------------------------------------------------------------"
    cat "$out_file"
    echo ""
    echo "==================== END CASE: $name ===================="
    echo ""
  } >> "$ACT_RESULT"

  # Per-case assertions (the bats suite re-asserts these and the exact values).
  if [[ "$rc" -ne 0 ]]; then
    echo "!!! act exited $rc for case $name" >&2
    overall_rc=1
  fi
  if ! grep -q "Job succeeded" "$out_file"; then
    echo "!!! no 'Job succeeded' found for case $name" >&2
    overall_rc=1
  fi

  rm -rf "$workdir"
  trap - EXIT
done

if [[ "$overall_rc" -eq 0 ]]; then
  echo "All act cases completed successfully. Artifact: $ACT_RESULT"
else
  echo "One or more act cases failed. See $ACT_RESULT" >&2
fi

exit "$overall_rc"
