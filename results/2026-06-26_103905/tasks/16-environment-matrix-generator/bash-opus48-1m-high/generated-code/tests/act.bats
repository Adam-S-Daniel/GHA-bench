#!/usr/bin/env bats
#
# act.bats -- end-to-end test of the GitHub Actions pipeline via nektos/act.
#
# Every assertion below is made against output produced by running the workflow
# inside a Docker container with `act` -- the script is exercised only through
# the pipeline, never directly. A single act run drives all fixture cases (the
# workflow loops over tests/expected.json), which keeps us within the act-run
# budget while still asserting exact expected values for each case.
#
# The full act output is saved to act-result.txt in the project root.

setup_file() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ROOT
  RESULT="$ROOT/act-result.txt"
  export RESULT

  # Build a clean temp git repo containing the project files + fixtures, so the
  # pipeline runs against a checkout exactly like GitHub would provide.
  REPO="$(mktemp -d)"
  export REPO
  cp -r "$ROOT/generate-matrix.sh" "$ROOT/matrix.jq" "$ROOT/.github" "$ROOT/tests" "$REPO/"
  [ -f "$ROOT/.actrc" ] && cp "$ROOT/.actrc" "$REPO/.actrc"

  (
    cd "$REPO"
    git init -q
    git config user.email ci@example.com
    git config user.name ci
    git add -A
    git commit -qm "fixture for act run"
  )

  # Run the pipeline once; capture everything to act-result.txt (overwrite at
  # the start of the run, then this file is the required artifact).
  {
    echo "############################################################"
    echo "# act push run -- environment-matrix-generator workflow"
    echo "############################################################"
  } > "$RESULT"

  (
    cd "$REPO"
    set -o pipefail
    act push --rm --pull=false 2>&1 | tee -a "$RESULT"
  )
  echo "$?" > "$REPO/.act_exit"
  export ACT_EXIT
  ACT_EXIT="$(cat "$REPO/.act_exit")"
}

teardown_file() {
  [ -n "${REPO:-}" ] && rm -rf "$REPO"
}

@test "act exited with code 0" {
  [ "$ACT_EXIT" -eq 0 ]
}

@test "act-result.txt artifact exists and is non-empty" {
  [ -s "$RESULT" ]
}

@test "every job reports success" {
  # Both the generate-matrix job and the dependent summary job must succeed.
  n="$(grep -c "Job succeeded" "$RESULT" || true)"
  [ "$n" -ge 2 ]
}

@test "basic.json case yields exactly 4 combinations" {
  grep -A2 "CASE basic.json" "$RESULT" | grep -q "TOTAL=4"
}

@test "exclude.json case yields exactly 3 combinations" {
  grep -A2 "CASE exclude.json" "$RESULT" | grep -q "TOTAL=3"
}

@test "include.json case yields exactly 6 combinations" {
  grep -A2 "CASE include.json" "$RESULT" | grep -q "TOTAL=6"
}

@test "strategy.json case has total 3, max-parallel 2, fail-fast false" {
  block="$(grep -A6 "CASE strategy.json" "$RESULT")"
  echo "$block" | grep -q "TOTAL=3"
  echo "$block" | grep -q "MAX_PARALLEL=2"
  echo "$block" | grep -q "FAIL_FAST=false"
}

@test "toobig.json case is rejected with exit 3 and max-size error" {
  block="$(grep -A4 "CASE toobig.json" "$RESULT")"
  echo "$block" | grep -q "EXIT=3"
  echo "$block" | grep -q "exceeds max-size"
}

@test "every fixture case passed inside the pipeline" {
  grep -q "OVERALL=PASS" "$RESULT"
}

@test "summary job printed the combination count from job outputs" {
  grep -q "matrix combinations" "$RESULT"
}
