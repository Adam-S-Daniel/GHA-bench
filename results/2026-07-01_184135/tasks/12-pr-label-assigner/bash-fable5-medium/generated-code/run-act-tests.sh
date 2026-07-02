#!/usr/bin/env bash
# run-act-tests.sh — end-to-end pipeline tests via nektos/act.
#
# For each test case this harness:
#   1. builds a temp git repo containing the project plus that case's
#      mocked changed-file list and rules (written into ci/),
#   2. runs `act push --rm` (the real GitHub Actions workflow),
#   3. appends the full act output to act-result.txt (delimited per case),
#   4. asserts act exited 0, the job reports "Job succeeded", and the label
#      set between LABELS_BEGIN/LABELS_END matches the case's EXACT
#      expected value (plus the exact LABEL_COUNT).
#
# Test cases (expected values derived from the rules semantics):
#   basic     docs/**->documentation, src/api/**->api,backend, *.test.*->tests
#             over 4 files  -> api backend documentation tests (count 4)
#   priority  exclusive '! vendor/**' beats docs/** and ** for vendored file
#             -> documentation touched vendored (count 3)
#   no-match  README.md/LICENSE match no rule -> empty set (count 0)

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

FAILURES=0

# assert LABEL CONDITION... — evaluate a test condition and report.
assert() {
  local desc=$1
  shift
  if "$@"; then
    echo "  PASS: $desc"
  else
    echo "  FAIL: $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# run_case NAME RULES_CONTENT FILES_CONTENT EXPECTED_LABELS EXPECTED_COUNT
run_case() {
  local name=$1 rules=$2 files=$3 expected_labels=$4 expected_count=$5
  local tmp output status actual_labels

  echo "=== case: $name ==="
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064  # expand $tmp now, not at trap time
  trap "rm -rf '$tmp'" RETURN

  # Assemble the project + this case's fixture data in a fresh git repo.
  cp -r "$ROOT/.github" "$ROOT/test" "$ROOT/label-assigner.sh" "$ROOT/.actrc" "$tmp/"
  mkdir -p "$tmp/ci"
  printf '%s\n' "$rules" > "$tmp/ci/labels.rules"
  printf '%s\n' "$files" > "$tmp/ci/changed-files.txt"
  git -C "$tmp" init -q -b main
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci add -A
  git -C "$tmp" -c user.email=ci@example.com -c user.name=ci commit -qm "case: $name"

  # Run the workflow through act; never let a failure kill the harness.
  status=0
  # --pull=false: the runner image is local-only; forced pulls fail auth.
  output=$( (cd "$tmp" && act push --rm --pull=false) 2>&1 ) || status=$?

  {
    echo "==================== CASE: $name ===================="
    echo "$output"
    echo "-------------------- exit code: $status --------------------"
  } >> "$RESULT_FILE"

  assert "act exited 0" [ "$status" -eq 0 ]
  assert "job reports 'Job succeeded'" grep -q "Job succeeded" <<<"$output"

  # Extract the label set the workflow printed (strip act's line prefixes).
  actual_labels=$(sed -n '/LABELS_BEGIN/,/LABELS_END/p' <<<"$output" \
    | sed '1d;$d' | sed 's/^.*| //')
  assert "label set is exactly [$expected_labels]" \
    [ "$actual_labels" = "$expected_labels" ]
  assert "label count is exactly $expected_count" \
    grep -q "LABEL_COUNT=$expected_count" <<<"$output"
  echo
}

command -v act >/dev/null || { echo "error: act not installed" >&2; exit 1; }

run_case basic \
  $'docs/** => documentation\nsrc/api/** => api, backend\n*.test.* => tests' \
  $'docs/guide/setup.md\nsrc/api/users.sh\nsrc/api/handlers/auth.test.js\nREADME.md' \
  $'api\nbackend\ndocumentation\ntests' \
  4

run_case priority \
  $'! vendor/** => vendored\ndocs/** => documentation\n** => touched' \
  $'vendor/docs/readme.md\ndocs/intro.md' \
  $'documentation\ntouched\nvendored' \
  3

run_case no-match \
  $'docs/** => documentation\nsrc/api/** => api, backend\n*.test.* => tests' \
  $'README.md\nLICENSE' \
  '' \
  0

echo "act output saved to $RESULT_FILE"
if [[ $FAILURES -gt 0 ]]; then
  echo "RESULT: $FAILURES assertion(s) failed" >&2
  exit 1
fi
echo "RESULT: all act pipeline assertions passed"
