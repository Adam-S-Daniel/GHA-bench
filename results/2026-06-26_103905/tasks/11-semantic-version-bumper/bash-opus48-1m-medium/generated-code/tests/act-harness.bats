#!/usr/bin/env bats
#
# End-to-end pipeline tests. Every assertion here flows THROUGH the GitHub
# Actions workflow executed locally with `act` (nektos/act). For each test case
# we build an isolated temp git repo containing the project files plus that
# case's fixture data, run `act push --rm`, append the full output to
# act-result.txt, and assert on the exact expected version + job success.
#
# NOTE: each test case is one `act push` invocation. Keep the case count small.

setup_file() {
  TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  REPO_ROOT="$( cd "$TEST_DIR/.." >/dev/null 2>&1 && pwd )"
  export REPO_ROOT
  export ACT_RESULT="$REPO_ROOT/act-result.txt"
  # Start each full run with a clean results artifact.
  : > "$ACT_RESULT"
}

# run_case <name> <fixture-subdir> <expected-version>
#
# Builds a temp git repo from the project + the named fixture, runs the
# workflow under act, records everything to act-result.txt, then asserts:
#   - act exited 0
#   - stdout contains the exact "NEW_VERSION=<expected>" marker
#   - every job reports "Job succeeded"
run_case() {
  local name="$1" fixture="$2" expected="$3"
  local work; work="$(mktemp -d)"

  # Assemble the isolated repo: script, workflow, act config, and fixtures.
  cp "$REPO_ROOT/bump-version.sh" "$work/"
  mkdir -p "$work/.github/workflows"
  cp "$REPO_ROOT/.github/workflows/semantic-version-bumper.yml" "$work/.github/workflows/"
  cp "$REPO_ROOT/.actrc" "$work/.actrc"
  cp -r "$REPO_ROOT/fixtures/$fixture/." "$work/"

  (
    cd "$work" || exit 1
    git init -q
    git config user.email ci@example.com
    git config user.name CI
    git add -A
    git commit -q -m "test: $name fixture"
  )

  # Run the pipeline; capture combined stdout+stderr. Use --pull=false so act
  # uses the locally-present runner image instead of trying to pull it.
  # The `if` guard keeps a non-zero act exit from aborting the test under
  # bats' errexit before we can record the output.
  local out status
  if out="$(cd "$work" && act push --rm --pull=false 2>&1)"; then
    status=0
  else
    status=$?
  fi

  # Append a clearly-delimited section to the required artifact.
  {
    echo "================================================================"
    echo "TEST CASE: $name  (fixture=$fixture, expected=$expected)"
    echo "act exit status: $status"
    echo "----------------------------------------------------------------"
    echo "$out"
    echo ""
  } >> "$ACT_RESULT"

  rm -rf "$work"

  # --- assertions ---
  # 1. act must succeed.
  [ "$status" -eq 0 ] || {
    echo "act exited $status for case $name" >&2
    echo "$out" >&2
    return 1
  }
  # 2. Exact expected version emitted by the workflow.
  echo "$out" | grep -qF "NEW_VERSION=$expected" || {
    echo "expected NEW_VERSION=$expected not found for case $name" >&2
    return 1
  }
  # 3. Every job must report success (validate + bump => at least 2).
  local succeeded
  succeeded="$(echo "$out" | grep -c 'Job succeeded')"
  [ "$succeeded" -ge 2 ] || {
    echo "expected >=2 'Job succeeded', got $succeeded for case $name" >&2
    return 1
  }
}

@test "pipeline: feat commit bumps 1.1.0 -> 1.2.0 (minor, VERSION file)" {
  run_case "minor-feat" "minor" "1.2.0"
}

@test "pipeline: breaking change bumps 1.1.0 -> 2.0.0 (major, VERSION file)" {
  run_case "major-breaking" "major" "2.0.0"
}

@test "pipeline: fix commit bumps 1.0.0 -> 1.0.1 (patch, package.json)" {
  run_case "patch-packagejson" "package" "1.0.1"
}
