#!/usr/bin/env bash
#
# run-act-tests.sh — end-to-end test harness that runs every test case
# through the GitHub Actions workflow via act (nektos/act).
#
# For each case it:
#   1. builds a temp git repo with the project files + case-specific
#      fixtures (the mocked "changed files" list and rules),
#   2. runs `act push --rm` (which runs the full bats unit suite in the
#      'test' job, then the labeler in the 'assign-labels' job),
#   3. appends the act output to act-result.txt,
#   4. asserts act exited 0, both jobs report "Job succeeded", and the
#      emitted label set matches the case's EXACT expected value.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$ROOT/act-result.txt"
: > "$RESULT_FILE"

failures=0
cases_run=0

fail() {
  echo "  FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "  ok: $*"
}

# Build a disposable git repo containing the project plus the given
# fixture files, run act in it, and capture output + exit code.
run_act_case() {
  local name=$1 rules=$2 changed=$3
  local tmp
  tmp="$(mktemp -d)"

  mkdir -p "$tmp/fixtures"
  cp -r "$ROOT/.github" "$ROOT/tests" "$ROOT/label-assigner.sh" "$tmp/"
  [[ -f "$ROOT/.actrc" ]] && cp "$ROOT/.actrc" "$tmp/"
  printf '%s\n' "$rules" > "$tmp/fixtures/labels.conf"
  printf '%s\n' "$changed" > "$tmp/fixtures/changed_files.txt"

  git -C "$tmp" init -q
  git -C "$tmp" -c user.email=test@example.com -c user.name=test \
    add -A
  git -C "$tmp" -c user.email=test@example.com -c user.name=test \
    commit -qm "fixture: $name"

  local output status
  # --pull=false: the runner image only exists locally; without it act
  # force-pulls and dies on registry auth.
  output="$(cd "$tmp" && act push --rm --pull=false 2>&1)"
  status=$?

  {
    echo "================================================================"
    echo "=== ACT TEST CASE: $name (exit code: $status)"
    echo "================================================================"
    echo "$output"
    echo
  } >> "$RESULT_FILE"

  rm -rf "$tmp"

  ACT_STATUS=$status
  ACT_OUTPUT=$output
}

# Extract the label set the workflow printed between its markers,
# stripping act's "[workflow/job]   | " line prefix.
extract_labels() {
  awk '/FINAL_LABELS_BEGIN/{f=1;next} /FINAL_LABELS_END/{f=0} f' <<< "$ACT_OUTPUT" \
    | sed -E 's/^\[[^]]*\][[:space:]]*\|[[:space:]]?//'
}

assert_common() {
  local succeeded
  if [[ $ACT_STATUS -eq 0 ]]; then
    pass "act exited 0"
  else
    fail "act exited $ACT_STATUS"
  fi
  succeeded=$(grep -c "Job succeeded" <<< "$ACT_OUTPUT")
  if [[ $succeeded -eq 2 ]]; then
    pass "both jobs report 'Job succeeded'"
  else
    fail "expected 2 'Job succeeded' lines, got $succeeded"
  fi
}

assert_labels() {
  local expected=$1 actual
  actual="$(extract_labels)"
  if [[ $actual == "$expected" ]]; then
    pass "label set is exactly $(printf '%s' "$expected" | tr '\n' ',' | sed 's/,$//;s/^$/<empty>/')"
  else
    fail "label mismatch: expected [$expected] got [$actual]"
  fi
}

# ---------------------------------------------------------------- case 1
# Basic mapping: three rule kinds (dir glob, dir glob with two labels,
# basename glob) each hit by one changed file.
echo "CASE 1: basic path-to-label mapping"
cases_run=$((cases_run + 1))
run_act_case "basic-mapping" \
'10|docs/**|documentation
20|src/api/**|api,backend
30|*.test.*|tests' \
'docs/guide/intro.md
src/api/users.py
src/ui/button.test.tsx'
assert_common
assert_labels 'api
backend
documentation
tests'

# ---------------------------------------------------------------- case 2
# Priority conflict: docs/api/readme.md matches all three rules, but the
# highest-priority rule is marked 'stop', so 'api' and 'markdown' must NOT
# be applied for it. src/api/handler.go still gets 'api' normally.
echo "CASE 2: priority ordering resolves conflicting rules"
cases_run=$((cases_run + 1))
run_act_case "priority-conflict" \
'10|docs/**|documentation|stop
20|**/api/**|api
30|*.md|markdown' \
'docs/api/readme.md
src/api/handler.go'
assert_common
assert_labels 'api
documentation'
if grep -q "markdown" <<< "$(extract_labels)"; then
  fail "suppressed label 'markdown' leaked into the label set"
else
  pass "suppressed label 'markdown' is absent"
fi

# ---------------------------------------------------------------- case 3
# No rule matches: the workflow must still succeed, emit an empty label
# set and print the 'no labels matched' notice.
echo "CASE 3: no matching rules yields an empty label set"
cases_run=$((cases_run + 1))
run_act_case "no-match" \
'10|docs/**|documentation' \
'Makefile
src/main.c'
assert_common
assert_labels ''
if grep -q "no labels matched" <<< "$ACT_OUTPUT"; then
  pass "'no labels matched' notice is present"
else
  fail "missing 'no labels matched' notice"
fi

# ------------------------------------------------------------------ done
echo
echo "act cases run: $cases_run, assertion failures: $failures"
echo "full act output saved to: $RESULT_FILE"
if [[ $failures -gt 0 ]]; then
  exit 1
fi
echo "ALL ACT TESTS PASSED"
