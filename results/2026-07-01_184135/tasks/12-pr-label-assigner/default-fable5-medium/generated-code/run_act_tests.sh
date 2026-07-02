#!/usr/bin/env bash
# End-to-end test harness: every test case runs THROUGH the GitHub Actions
# workflow via `act` (never by invoking labeler.py directly).
#
# For each fixtures/case*/ directory it:
#   1. builds a temp git repo containing the project + that case's mocked
#      changed-file list
#   2. runs `act push --rm`, appending the output to act-result.txt
#   3. asserts: act exit code 0, the EXACT expected FINAL_LABELS line,
#      the error-path marker, and "Job succeeded"
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
RESULT="$ROOT/act-result.txt"
: > "$RESULT"

FAILURES=0

for case_dir in "$ROOT"/fixtures/case*/; do
  case_name="$(basename "$case_dir")"
  expected="$(cat "$case_dir/expected.txt")"

  echo "=== Running $case_name (expected: $expected) ==="

  # 1. Temp git repo with project files + this case's fixture data.
  tmp="$(mktemp -d)"
  cp "$ROOT"/labeler.py "$ROOT"/test_labeler.py "$ROOT"/rules.json "$ROOT"/.actrc "$tmp/"
  mkdir -p "$tmp/.github/workflows"
  cp "$ROOT"/.github/workflows/pr-label-assigner.yml "$tmp/.github/workflows/"
  cp "$case_dir/changed_files.txt" "$tmp/changed_files.txt"
  git -C "$tmp" init -q
  git -C "$tmp" -c user.email=t@t -c user.name=t add -A
  git -C "$tmp" -c user.email=t@t -c user.name=t commit -qm "fixture: $case_name"

  # 2. Run the workflow through act, capture everything.
  {
    echo "===================================================================="
    echo "=== TEST CASE: $case_name"
    echo "=== EXPECTED : $expected"
    echo "===================================================================="
  } >> "$RESULT"
  # --pull=false: the runner image is local-only; pulling would hit registry auth.
  (cd "$tmp" && act push --rm --pull=false) >> "$RESULT" 2>&1
  act_exit=$?
  echo "=== ACT EXIT CODE ($case_name): $act_exit" >> "$RESULT"
  rm -rf "$tmp"

  # 3. Assertions against the captured output.
  case_output="$(awk "/=== TEST CASE: $case_name\$/,0" "$RESULT")"

  if [ "$act_exit" -ne 0 ]; then
    echo "FAIL [$case_name]: act exited with $act_exit"; FAILURES=$((FAILURES+1)); continue
  fi
  if ! grep -qF "$expected" <<<"$case_output"; then
    echo "FAIL [$case_name]: exact line '$expected' not found in act output"
    FAILURES=$((FAILURES+1)); continue
  fi
  if ! grep -qF "ERROR_PATH_OK" <<<"$case_output"; then
    echo "FAIL [$case_name]: error-path marker ERROR_PATH_OK missing"
    FAILURES=$((FAILURES+1)); continue
  fi
  if ! grep -qF "Job succeeded" <<<"$case_output"; then
    echo "FAIL [$case_name]: 'Job succeeded' missing"
    FAILURES=$((FAILURES+1)); continue
  fi
  echo "PASS [$case_name]"
done

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL ACT TEST CASES PASSED (results in act-result.txt)"
else
  echo "$FAILURES act test case(s) FAILED (see act-result.txt)"
fi
exit "$FAILURES"
