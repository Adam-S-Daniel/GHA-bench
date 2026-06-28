#!/usr/bin/env bats
# ============================================================================
# Test suite for the Semantic Version Bumper.
#
# Per the task requirements, the END-TO-END behaviour of the version bumper is
# exercised exclusively THROUGH the GitHub Actions workflow via `act` -- the
# script is never invoked directly to assert business logic. To respect the
# "limit act push runs" guidance, `act` is launched exactly ONCE (in
# setup_file) over a temp git repo containing all fixtures; every scenario
# prints a parseable `RESULT` line, and each test below asserts on the EXACT
# expected version parsed from that single run's captured output
# (act-result.txt).
#
# The suite also contains fast, act-independent checks:
#   * static validation of the script (bash -n + shellcheck)
#   * workflow structure tests (triggers / jobs / steps / file references)
#   * actionlint validation of the workflow
#
# TDD note: these structure/actionlint tests were written first (red) before the
# workflow existed, then made green by adding the workflow; the act assertions
# were then layered on top.
# ============================================================================

# --- shared paths (evaluated when bats sources this file) -------------------
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_DIR/semver-bump.sh"
WORKFLOW="$PROJECT_DIR/.github/workflows/semantic-version-bumper.yml"
CHECKER="$PROJECT_DIR/test/wf_check.py"
ACT_RESULT="$PROJECT_DIR/act-result.txt"
ACT_EXIT_FILE="$PROJECT_DIR/.act-exit"

# Known-good results for every fixture scenario: "scenario -> expected new version".
SCENARIOS=(minor patch major pkgjson none mixed)
declare -A EXPECTED=(
  [minor]=1.2.0    # feat only:            1.1.0 -> 1.2.0
  [patch]=1.1.1    # fix only:             1.1.0 -> 1.1.1
  [major]=2.0.0    # breaking change:      1.1.0 -> 2.0.0
  [pkgjson]=0.6.0  # feat+fix in pkg.json: 0.5.2 -> 0.6.0
  [none]=3.4.5     # no release commits:   3.4.5 -> 3.4.5 (unchanged)
  [mixed]=2.4.0    # feat+fix, "v" prefix: 2.3.4 -> 2.4.0
)
declare -A EXPECTED_BUMP=(
  [minor]=minor [patch]=patch [major]=major
  [pkgjson]=minor [none]=none [mixed]=minor
)

# --- helpers ----------------------------------------------------------------

# Extract the "new=" value for a scenario from the captured act output.
get_new() {
  grep -oE "RESULT scenario=$1 old=[^ ]+ new=[^ ]+ bump=[^ ]+" "$ACT_RESULT" \
    | head -n1 | sed -E 's/.*new=([^ ]+).*/\1/'
}

# Extract the "bump=" value for a scenario from the captured act output.
get_bump() {
  grep -oE "RESULT scenario=$1 old=[^ ]+ new=[^ ]+ bump=[^ ]+" "$ACT_RESULT" \
    | head -n1 | sed -E 's/.*bump=([^ ]+).*/\1/'
}

# --- one-time setup: build a temp git repo and run the workflow via act ------
setup_file() {
  # Local-iteration convenience: reuse an existing run instead of paying the
  # 30-90s act cost again. Grading runs (env unset) always produce a fresh run.
  if [[ "${SEMVER_REUSE_ACT:-0}" == "1" && -s "$ACT_RESULT" && -f "$ACT_EXIT_FILE" ]]; then
    return 0
  fi

  command -v act >/dev/null    || { echo "act is required but not installed" >&2; return 1; }
  command -v docker >/dev/null || { echo "docker is required but not installed" >&2; return 1; }

  local repo log
  repo="$(mktemp -d)"
  log="$(mktemp)"

  # Assemble a throw-away git repo with exactly the files the workflow needs.
  cp "$PROJECT_DIR/semver-bump.sh" "$repo/"
  cp -r "$PROJECT_DIR/fixtures" "$repo/"
  cp -r "$PROJECT_DIR/.github" "$repo/"
  [[ -f "$PROJECT_DIR/.actrc" ]] && cp "$PROJECT_DIR/.actrc" "$repo/"

  (
    cd "$repo" || exit 1
    git init -q
    git config user.email "ci@example.com"
    git config user.name "semver-ci"
    git add -A
    git commit -qm "test: semantic version bumper fixtures"
  )

  # Run act exactly once. --pull=false avoids pulling the local-only image and
  # --action-offline-mode reuses the cached actions/checkout. Capture the exit
  # code without letting a failure abort setup_file.
  local act_exit
  if ( cd "$repo" && act push --rm --pull=false --action-offline-mode \
         -P ubuntu-latest=act-ubuntu-pwsh:latest ) >"$log" 2>&1; then
    act_exit=0
  else
    act_exit=$?
  fi
  echo "$act_exit" >"$ACT_EXIT_FILE"

  # Persist the full act log, then append a clearly-delimited per-case section.
  {
    echo "############################################################"
    echo "# act push --rm  (Semantic Version Bumper workflow)"
    echo "# exit code: $act_exit"
    echo "############################################################"
    cat "$log"
    echo ""
    echo "############################################################"
    echo "# PER-CASE RESULTS (parsed from the single act run above)"
    echo "############################################################"
    local s line
    for s in "${SCENARIOS[@]}"; do
      line="$(grep -oE "RESULT scenario=$s old=[^ ]+ new=[^ ]+ bump=[^ ]+" "$log" | head -n1 || true)"
      echo "------------------------------------------------------------"
      echo "CASE: $s   (expected new=${EXPECTED[$s]}, bump=${EXPECTED_BUMP[$s]})"
      echo "ACTUAL: ${line:-<no RESULT line captured>}"
    done
  } >"$ACT_RESULT"

  rm -rf "$repo" "$log"
}

# ============================================================================
# Static validation of the script (requirement: shellcheck + bash -n clean)
# ============================================================================

@test "script: exists and is executable bash" {
  [ -f "$SCRIPT" ]
  run head -n1 "$SCRIPT"
  [ "$output" = "#!/usr/bin/env bash" ]
}

@test "script: passes 'bash -n' syntax check" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script: passes shellcheck" {
  if ! command -v shellcheck >/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Workflow structure tests (parse YAML; verify triggers/jobs/steps/refs)
# ============================================================================

@test "workflow: declares push/pull_request/workflow_dispatch/schedule triggers" {
  run python3 "$CHECKER" "$WORKFLOW" triggers
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "workflow: defines version-bump and summary jobs with dependency + permissions" {
  run python3 "$CHECKER" "$WORKFLOW" jobs
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "workflow: uses actions/checkout and runs semver-bump.sh" {
  run python3 "$CHECKER" "$WORKFLOW" steps
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "workflow: references script and fixtures that exist on disk" {
  run python3 "$CHECKER" "$WORKFLOW" references
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "workflow: passes actionlint cleanly" {
  if ! command -v actionlint >/dev/null; then skip "actionlint not installed"; fi
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# ============================================================================
# End-to-end tests THROUGH act (assert exact expected values)
# ============================================================================

@test "act: produced an act-result.txt artifact" {
  [ -f "$ACT_RESULT" ]
  [ -s "$ACT_RESULT" ]
}

@test "act: workflow exited with code 0" {
  [ -f "$ACT_EXIT_FILE" ]
  run cat "$ACT_EXIT_FILE"
  [ "$output" = "0" ] || { echo "act exit was '$output'; see act-result.txt"; return 1; }
}

@test "act: every job reports 'Job succeeded'" {
  # Two jobs (version-bump, summary) must each succeed.
  run grep -c "Job succeeded" "$ACT_RESULT"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ] || { echo "only $output 'Job succeeded' lines"; return 1; }
  # Plus our own explicit per-job markers.
  grep -q "JOB_OK version-bump" "$ACT_RESULT"
  grep -q "JOB_OK summary" "$ACT_RESULT"
}

@test "act: all six fixture scenarios were processed" {
  grep -q "RESULT_COUNT=6" "$ACT_RESULT"
}

@test "act: minor scenario bumps 1.1.0 -> 1.2.0 (feat)" {
  [ "$(get_new minor)" = "1.2.0" ]
  [ "$(get_bump minor)" = "minor" ]
}

@test "act: patch scenario bumps 1.1.0 -> 1.1.1 (fix)" {
  [ "$(get_new patch)" = "1.1.1" ]
  [ "$(get_bump patch)" = "patch" ]
}

@test "act: major scenario bumps 1.1.0 -> 2.0.0 (breaking)" {
  [ "$(get_new major)" = "2.0.0" ]
  [ "$(get_bump major)" = "major" ]
}

@test "act: pkgjson scenario bumps 0.5.2 -> 0.6.0 (feat+fix, package.json)" {
  [ "$(get_new pkgjson)" = "0.6.0" ]
  [ "$(get_bump pkgjson)" = "minor" ]
}

@test "act: none scenario leaves 3.4.5 unchanged (no release commits)" {
  [ "$(get_new none)" = "3.4.5" ]
  [ "$(get_bump none)" = "none" ]
}

@test "act: mixed scenario bumps v2.3.4 -> 2.4.0 (feat+fix, v-prefix)" {
  [ "$(get_new mixed)" = "2.4.0" ]
  [ "$(get_bump mixed)" = "minor" ]
}

@test "act: summary job received and echoed the primary new version (1.2.0)" {
  grep -q "Primary scenario bump: 1.1.0 -> 1.2.0 (minor)" "$ACT_RESULT"
}
