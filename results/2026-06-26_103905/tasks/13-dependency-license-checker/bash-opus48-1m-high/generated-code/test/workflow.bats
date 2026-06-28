#!/usr/bin/env bats
#
# Workflow tests for the Dependency License Checker.
#
# Two kinds of tests live here:
#   1. Structure tests   - parse the workflow YAML and assert on its shape,
#                          verify referenced script paths exist, and confirm
#                          actionlint passes. These are fast (no Docker).
#   2. Integration tests - drive the workflow end-to-end through `act` in a
#                          throwaway git repo for each fixture case, append all
#                          output to act-result.txt, and assert on the EXACT
#                          expected report values plus "Job succeeded".

WORKFLOW=".github/workflows/dependency-license-checker.yml"

# Absolute path to the project root (the directory containing this test dir).
project_root() {
  cd "$BATS_TEST_DIRNAME/.." && pwd
}

setup_file() {
  # Truncate the required act-result.txt artifact once per run.
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  : > "$ROOT/act-result.txt"
}

# --- helper: run the workflow through act for one fixture case -------------
# Usage: run_act_case LABEL [extra act args...]
# Sets globals ACT_OUT (combined output) and ACT_STATUS (act exit code), and
# appends a clearly delimited section to act-result.txt.
run_act_case() {
  local label="$1"; shift
  local root tmp
  root="$(project_root)"
  tmp="$(mktemp -d)"

  # Assemble a minimal but complete copy of the project.
  cp "$root/license-checker.sh" "$tmp/"
  cp "$root/.actrc" "$tmp/.actrc"
  mkdir -p "$tmp/.github/workflows" "$tmp/test/fixtures"
  cp "$root/$WORKFLOW" "$tmp/.github/workflows/"
  cp "$root"/test/fixtures/* "$tmp/test/fixtures/"

  # act/checkout need a real commit to operate on.
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "tester@example.test"
  git -C "$tmp" config user.name "tester"
  git -C "$tmp" add -A
  git -C "$tmp" commit -q -m "fixture for $label"

  # Run the workflow's push event; capture stdout+stderr and the exit code.
  # --pull=false: the act image is built locally and must not be re-pulled.
  # The if/else keeps a non-zero act exit from aborting the bats test before
  # we have captured and persisted the output.
  local out status
  if out="$(cd "$tmp" && act push --rm --pull=false "$@" 2>&1)"; then
    status=0
  else
    status=$?
  fi

  {
    echo "================================================================"
    echo "ACT TEST CASE: $label"
    echo "ACT ARGS: $*"
    echo "ACT EXIT CODE: $status"
    echo "----------------------------------------------------------------"
    echo "$out"
    echo
  } >> "$root/act-result.txt"

  ACT_OUT="$out"
  ACT_STATUS="$status"
  rm -rf "$tmp"
}

# ==========================================================================
# Structure tests (fast, no Docker)
# ==========================================================================

@test "structure: workflow file exists and is valid YAML" {
  [ -f "$(project_root)/$WORKFLOW" ]
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" \
        "$(project_root)/$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "structure: declares push, pull_request, schedule and workflow_dispatch triggers" {
  run python3 - "$(project_root)/$WORKFLOW" <<'PY'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1]))
# PyYAML parses the bare `on:` key as boolean True.
on = wf.get(True, wf.get("on"))
assert isinstance(on, dict), on
for trig in ("push", "pull_request", "schedule", "workflow_dispatch"):
    assert trig in on, f"missing trigger: {trig}"
PY
  [ "$status" -eq 0 ]
}

@test "structure: defines license-check and enforce-policy jobs with a dependency" {
  run python3 - "$(project_root)/$WORKFLOW" <<'PY'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf["jobs"]
assert "license-check" in jobs, "missing license-check job"
assert "enforce-policy" in jobs, "missing enforce-policy job"
# enforce-policy must depend on license-check.
needs = jobs["enforce-policy"].get("needs")
needs = [needs] if isinstance(needs, str) else needs
assert needs and "license-check" in needs, f"bad needs: {needs}"
PY
  [ "$status" -eq 0 ]
}

@test "structure: has read permissions and uses actions/checkout@v4" {
  run python3 - "$(project_root)/$WORKFLOW" <<'PY'
import yaml, sys
wf = yaml.safe_load(open(sys.argv[1]))
assert wf.get("permissions", {}).get("contents") == "read", wf.get("permissions")
steps = wf["jobs"]["license-check"]["steps"]
uses = [s.get("uses", "") for s in steps]
assert any(u == "actions/checkout@v4" for u in uses), uses
PY
  [ "$status" -eq 0 ]
}

@test "structure: workflow invokes license-checker.sh and the script exists" {
  local root; root="$(project_root)"
  grep -q "license-checker.sh" "$root/$WORKFLOW"
  [ -f "$root/license-checker.sh" ]
  # Every config path referenced via env defaults must exist.
  [ -f "$root/test/fixtures/allow-list.txt" ]
  [ -f "$root/test/fixtures/deny-list.txt" ]
  [ -f "$root/test/fixtures/license-db.csv" ]
  [ -f "$root/test/fixtures/package.json" ]
  [ -f "$root/test/fixtures/requirements.txt" ]
}

@test "structure: actionlint passes cleanly" {
  run actionlint "$(project_root)/$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ==========================================================================
# Integration tests (through act) - one act run per fixture case
# ==========================================================================

@test "act: npm manifest produces the exact expected compliance report" {
  run_act_case "npm-package.json"

  # The whole pipeline must succeed.
  [ "$ACT_STATUS" -eq 0 ]

  # Both jobs must report success.
  local succeeded
  succeeded="$(grep -c "Job succeeded" <<< "$ACT_OUT")"
  [ "$succeeded" -ge 2 ]

  # Exact manifest + summary + result.
  grep -q "Manifest: test/fixtures/package.json (npm)" <<< "$ACT_OUT"
  grep -q "Summary: total=4 approved=2 denied=1 unknown=1" <<< "$ACT_OUT"
  grep -q "Result: FAIL" <<< "$ACT_OUT"

  # Exact per-dependency classifications.
  grep -Eq "left-pad[[:space:]]+1\.3\.0[[:space:]]+MIT[[:space:]]+APPROVED" <<< "$ACT_OUT"
  grep -Eq "axios[[:space:]]+1\.6\.0[[:space:]]+Apache-2\.0[[:space:]]+APPROVED" <<< "$ACT_OUT"
  grep -Eq "copyleft-lib[[:space:]]+2\.0\.0[[:space:]]+GPL-3\.0[[:space:]]+DENIED" <<< "$ACT_OUT"
  grep -Eq "mystery-pkg[[:space:]]+0\.0\.1[[:space:]]+-[[:space:]]+UNKNOWN" <<< "$ACT_OUT"

  # The dependent job must surface the FAIL result.
  grep -q "Compliance gate result: FAIL" <<< "$ACT_OUT"
}

@test "act: pip manifest (requirements.txt) produces the exact expected report" {
  run_act_case "pip-requirements.txt" --env "MANIFEST=test/fixtures/requirements.txt"

  [ "$ACT_STATUS" -eq 0 ]

  local succeeded
  succeeded="$(grep -c "Job succeeded" <<< "$ACT_OUT")"
  [ "$succeeded" -ge 2 ]

  grep -q "Manifest: test/fixtures/requirements.txt (pip)" <<< "$ACT_OUT"
  grep -q "Summary: total=4 approved=2 denied=1 unknown=1" <<< "$ACT_OUT"
  grep -q "Result: FAIL" <<< "$ACT_OUT"

  grep -Eq "requests[[:space:]]+2\.31\.0[[:space:]]+Apache-2\.0[[:space:]]+APPROVED" <<< "$ACT_OUT"
  grep -Eq "flask[[:space:]]+2\.3\.0[[:space:]]+BSD-3-Clause[[:space:]]+APPROVED" <<< "$ACT_OUT"
  grep -Eq "copyleft-py[[:space:]]+1\.0\.0[[:space:]]+GPL-3\.0[[:space:]]+DENIED" <<< "$ACT_OUT"
  grep -Eq "ghost-pkg[[:space:]]+0\.1\.0[[:space:]]+-[[:space:]]+UNKNOWN" <<< "$ACT_OUT"
}
