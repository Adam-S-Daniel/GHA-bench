#!/usr/bin/env bash
# Integration test harness: runs every functional test case through the
# GitHub Actions workflow with `act` (nektos/act).
#
# For each case it:
#   1. builds a throwaway git repo containing the project + that case's fixture,
#   2. runs `act push --rm`, capturing output (appended to act-result.txt),
#   3. asserts act exited 0, the job succeeded, and the EXACT expected version /
#      bump type appear in the output.
#
# There are exactly 3 functional cases => exactly 3 `act push` runs.
set -u

# Resolve project root (directory containing this script).
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$PROJECT_DIR/act-result.txt"
WORKFLOW=".github/workflows/semantic-version-bumper.yml"

# Fresh result log each run.
: > "$RESULT_FILE"

PASS=0
FAIL=0

# fail <message>
fail() { echo "ASSERT FAIL: $1" | tee -a "$RESULT_FILE"; FAIL=$((FAIL + 1)); }
ok()   { echo "ASSERT OK:   $1" | tee -a "$RESULT_FILE"; PASS=$((PASS + 1)); }

# run_case <name> <start_version> <fixture> <version_filename> <expected_new> <expected_type>
run_case() {
  local name="$1" start="$2" fixture="$3" vfile="$4" expected="$5" etype="$6"

  echo ""
  echo "############################################################"
  echo "# CASE: $name  (start=$start  expect=$expected/$etype)"
  echo "############################################################"

  {
    echo ""
    echo "############################################################"
    echo "# CASE: $name"
    echo "#   start version : $start"
    echo "#   version file  : $vfile"
    echo "#   fixture       : $fixture"
    echo "#   expected      : NEW_VERSION=$expected  BUMP_TYPE=$etype"
    echo "############################################################"
  } >> "$RESULT_FILE"

  # 1. Build an isolated git repo with project files + this case's fixture.
  local tmp
  tmp="$(mktemp -d)"
  cp -r "$PROJECT_DIR/src" "$PROJECT_DIR/test" "$PROJECT_DIR/fixtures" \
        "$PROJECT_DIR/package.json" "$PROJECT_DIR/.github" "$tmp/"
  cp "$PROJECT_DIR/.actrc" "$tmp/.actrc"

  # The script auto-detects the version file: a plain VERSION file takes
  # precedence, otherwise it falls back to package.json. So for the
  # package.json case we embed the version there and create NO VERSION file.
  if [ "$vfile" = "package.json" ]; then
    node -e "const f='$tmp/package.json';const p=require(f);p.version='$start';require('fs').writeFileSync(f,JSON.stringify(p,null,2)+'\n')"
  else
    printf '%s\n' "$start" > "$tmp/$vfile"
  fi
  cp "$PROJECT_DIR/fixtures/$fixture" "$tmp/commits.log"

  # act / checkout@v4 need a real git repo.
  (cd "$tmp" && git init -q && git config user.email t@t.t && git config user.name t \
     && git add -A && git commit -qm "case: $name")

  # 2. Run the pipeline.
  local out rc
  out="$tmp/act.out"
  # --pull=false: the runner image is built locally (act-ubuntu-pwsh:latest) and
  # is not in any registry, so act must NOT try to force-pull it.
  (cd "$tmp" && act push --rm --pull=false -W "$WORKFLOW") > "$out" 2>&1
  rc=$?

  # 3. Capture full output, then assert.
  cat "$out" >> "$RESULT_FILE"

  if [ "$rc" -eq 0 ]; then ok "[$name] act exit code 0"; else fail "[$name] act exit code was $rc (expected 0)"; fi
  if grep -q "NEW_VERSION=$expected" "$out"; then ok "[$name] NEW_VERSION=$expected"; else fail "[$name] expected NEW_VERSION=$expected not found"; fi
  if grep -q "BUMP_TYPE=$etype" "$out"; then ok "[$name] BUMP_TYPE=$etype"; else fail "[$name] expected BUMP_TYPE=$etype not found"; fi
  if grep -q "Job succeeded" "$out"; then ok "[$name] Job succeeded"; else fail "[$name] 'Job succeeded' not found"; fi

  rm -rf "$tmp"
}

# --- The three functional cases -------------------------------------------
# feat -> minor, fix -> patch, breaking -> major. Distinct start versions so a
# stale/cached result can't accidentally satisfy a different case.
run_case "minor-feat"    "1.1.0" "minor.commits.log" "VERSION"      "1.2.0" "minor"
run_case "patch-fix"     "2.3.4" "patch.commits.log" "VERSION"      "2.3.5" "patch"
run_case "major-breaking" "1.4.9" "major.commits.log" "package.json" "2.0.0" "major"

# --- Summary ---------------------------------------------------------------
{
  echo ""
  echo "############################################################"
  echo "# SUMMARY: $PASS passed, $FAIL failed"
  echo "############################################################"
} | tee -a "$RESULT_FILE"

[ "$FAIL" -eq 0 ]
