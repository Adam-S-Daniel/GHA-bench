#!/usr/bin/env bash
#
# run-act-tests.sh
#
# End-to-end test harness: runs the GitHub Actions workflow through `act` for a
# set of fixture cases. For each case it builds an isolated temp git repo
# containing the project files plus that case's secret config, runs
# `act push --rm`, and asserts on the EXACT report values the workflow emits.
#
# All act output is appended (clearly delimited) to act-result.txt in the
# project directory. The harness fails (exit 1) if any case fails an assertion.
#
# NOTE: limited to 3 act runs (one per case) by design.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT="$ROOT/act-result.txt"
# Accumulate into a private buffer first, then publish to act-result.txt in a
# single write at the end. This keeps the artifact clean even if other
# processes happen to touch the same directory concurrently.
RESULT_TMP="$(mktemp)"
trap 'rm -f "$RESULT_TMP"' EXIT

# Unique container/volume namespace for this workflow (matches the "srv18b"
# nonce in the workflow + job names) so act never collides with unrelated runs.
WF_SLUG="Secret-Rotation-Validator-srv18b"

# Each case: "<name>|<fixture-relative-to-root>|<exp_expired> <exp_warning> <exp_ok>"
# Expected summaries assume the workflow's fixed defaults: NOW=2024-02-10,
# WARNING_DAYS=14 (push events do not receive workflow_dispatch inputs).
CASES=(
  "mixed|config/secrets.json|1 1 1"
  "all-ok|tests/cases/all-ok.json|0 0 2"
  "all-expired|tests/cases/all-expired.json|3 0 0"
)

fail() { echo "HARNESS FAIL: $*" >&2; exit 1; }

overall_rc=0

for case in "${CASES[@]}"; do
  name="${case%%|*}"
  rest="${case#*|}"
  fixture="${rest%%|*}"
  expected="${rest##*|}"
  read -r exp_e exp_w exp_o <<< "$expected"

  echo "=========================================================="
  echo "Running act case: $name (expecting expired=$exp_e warning=$exp_w ok=$exp_o)"
  echo "=========================================================="

  # Build an isolated temp git repo with the project files + this case's config.
  work="$(mktemp -d)"
  cp "$ROOT/secret-rotation-validator.sh" "$work/"
  cp "$ROOT/.actrc" "$work/"
  mkdir -p "$work/.github/workflows" "$work/config" "$work/fixtures" "$work/tests"
  cp "$ROOT/.github/workflows/secret-rotation-validator.yml" "$work/.github/workflows/"
  cp "$ROOT/fixtures/secrets.json" "$work/fixtures/"
  cp -r "$ROOT/tests/." "$work/tests/"
  # This case's data becomes the workflow's config target.
  cp "$ROOT/$fixture" "$work/config/secrets.json"

  (
    cd "$work" || exit 1
    git init -q
    git config user.email "ci@example.com"
    git config user.name "ci"
    git add -A
    git commit -q -m "case $name"
  ) || fail "git setup failed for case $name"

  # Delimit this case's output in the buffer.
  {
    echo ""
    echo "################################################################"
    echo "# ACT CASE: $name  (fixture: $fixture)"
    echo "# expected: expired=$exp_e warning=$exp_w ok=$exp_o"
    echo "################################################################"
  } >> "$RESULT_TMP"

  # Remove only THIS workflow's own stale volumes (scoped to our unique slug so
  # unrelated concurrent runs are never disturbed) before launching act.
  for v in $(docker volume ls -q | grep "$WF_SLUG" || true); do
    docker volume rm "$v" >/dev/null 2>&1 || true
  done

  # Run the workflow. Capture combined output for parsing AND the buffer.
  out="$(cd "$work" && act push --rm --pull=false 2>&1)"
  rc=$?
  printf '%s\n' "$out" >> "$RESULT_TMP"

  rm -rf "$work"

  # --- Assertions -------------------------------------------------------
  if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] act exit code was $rc (expected 0)"
    overall_rc=1
    continue
  fi
  echo "  [ok] act exit code 0"

  marker="ROTATION_SUMMARY expired=$exp_e warning=$exp_w ok=$exp_o"
  if grep -qF "$marker" <<< "$out"; then
    echo "  [ok] found exact summary: $marker"
  else
    echo "  [FAIL] expected summary line not found: $marker"
    echo "         actual summary lines:"
    grep -F "ROTATION_SUMMARY" <<< "$out" | sed 's/^/           /' || true
    overall_rc=1
  fi

  # Both jobs (test, report) must report success.
  succeeded="$(grep -c "Job succeeded" <<< "$out")"
  if [ "$succeeded" -ge 2 ]; then
    echo "  [ok] $succeeded jobs reported 'Job succeeded'"
  else
    echo "  [FAIL] expected >=2 'Job succeeded', found $succeeded"
    overall_rc=1
  fi
done

# Publish the accumulated output to the required artifact in one write.
cp "$RESULT_TMP" "$RESULT"

echo ""
if [ "$overall_rc" -eq 0 ]; then
  echo "ALL ACT CASES PASSED"
else
  echo "ONE OR MORE ACT CASES FAILED"
fi
exit "$overall_rc"
