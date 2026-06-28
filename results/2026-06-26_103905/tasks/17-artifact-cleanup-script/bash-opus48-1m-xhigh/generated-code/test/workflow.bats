#!/usr/bin/env bats
#
# Workflow tests for .github/workflows/artifact-cleanup-script.yml
#
#   * Structure tests   — parse the YAML and assert on triggers/jobs/steps and
#                         that referenced files exist (fast, no Docker).
#   * actionlint test   — assert the workflow lints clean (exit 0).
#   * act integration   — for each fixture case, build a temp git repo, run the
#                         pipeline end-to-end with `act push --rm`, append the
#                         output to act-result.txt, and assert EXACT values plus
#                         "Job succeeded" for every job.
#
# NOTE: PyYAML parses the YAML 1.1 key `on:` as the boolean True, so the trigger
# block is looked up as wf.get('on', wf.get(True)).

setup_file() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PROJECT_ROOT
  export WF="$PROJECT_ROOT/.github/workflows/artifact-cleanup-script.yml"
  export ACT_RESULT="$PROJECT_ROOT/act-result.txt"
  # The act-result.txt artifact is rebuilt fresh for each full run of this file.
  : > "$ACT_RESULT"
}

# ---------------------------------------------------------------------------
# Structure tests (YAML parsing)
# ---------------------------------------------------------------------------

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "workflow declares the expected trigger events" {
  run python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
triggers = wf.get('on', wf.get(True))
assert isinstance(triggers, dict), f"expected mapping of triggers, got {type(triggers)}"
for t in ('push', 'pull_request', 'schedule', 'workflow_dispatch'):
    assert t in triggers, f"missing trigger: {t}"
print("triggers ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"triggers ok"* ]]
}

@test "workflow defines validate and cleanup jobs with a dependency" {
  run python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
jobs = wf['jobs']
assert 'validate' in jobs, "missing job: validate"
assert 'cleanup' in jobs, "missing job: cleanup"
needs = jobs['cleanup'].get('needs')
needs = [needs] if isinstance(needs, str) else (needs or [])
assert 'validate' in needs, f"cleanup must need validate, got {needs}"
print("jobs ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs ok"* ]]
}

@test "workflow declares permissions" {
  run python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
assert 'permissions' in wf, "workflow must declare permissions"
print("permissions ok")
PY
  [ "$status" -eq 0 ]
}

@test "every job checks out the repo with actions/checkout@v4" {
  run python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for name, job in wf['jobs'].items():
    uses = [s.get('uses', '') for s in job.get('steps', [])]
    assert 'actions/checkout@v4' in uses, f"job {name} does not use actions/checkout@v4"
print("checkout ok")
PY
  [ "$status" -eq 0 ]
}

@test "workflow references the cleanup script and its path exists" {
  run python3 - "$WF" "$PROJECT_ROOT" <<'PY'
import sys, yaml, os
wf = yaml.safe_load(open(sys.argv[1]))
root = sys.argv[2]
runs = []
for job in wf['jobs'].values():
    for step in job.get('steps', []):
        if 'run' in step:
            runs.append(step['run'])
blob = "\n".join(runs)
assert 'artifact-cleanup.sh' in blob, "no step runs artifact-cleanup.sh"
assert os.path.isfile(os.path.join(root, 'artifact-cleanup.sh')), "artifact-cleanup.sh not found on disk"
print("script reference ok")
PY
  [ "$status" -eq 0 ]
}

@test "fixture files referenced by the workflow env exist on disk" {
  run python3 - "$WF" "$PROJECT_ROOT" <<'PY'
import sys, yaml, os
wf = yaml.safe_load(open(sys.argv[1]))
root = sys.argv[2]
env = wf.get('env', {})
for key in ('INVENTORY', 'POLICY'):
    assert key in env, f"workflow env missing {key}"
    assert os.path.isfile(os.path.join(root, env[key])), f"{env[key]} not found"
print("fixtures ok")
PY
  [ "$status" -eq 0 ]
}

@test "actionlint passes on the workflow (exit 0)" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# act integration harness
# ---------------------------------------------------------------------------

# Build an isolated git repo for the given case, run the workflow through act,
# capture output into ACT_OUTPUT / ACT_STATUS, and append it to act-result.txt.
run_case() {
  local case="$1"
  local work
  work="$(mktemp -d)"
  mkdir -p "$work/.github/workflows" "$work/fixtures"
  cp "$PROJECT_ROOT/artifact-cleanup.sh" "$work/"
  cp "$WF" "$work/.github/workflows/"
  # Per-case fixture data drives the otherwise-static workflow.
  cp "$PROJECT_ROOT/test/fixtures/case${case}.txt" "$work/fixtures/artifacts.txt"
  cp "$PROJECT_ROOT/test/fixtures/case${case}.env" "$work/fixtures/policy.env"

  ( cd "$work" \
      && git init -q \
      && git add -A \
      && git -c user.email=ci@example.com -c user.name=ci commit -qm "case $case" \
  ) >/dev/null 2>&1

  ACT_OUTPUT="$( cd "$work" && act push --rm \
      -P ubuntu-latest=act-ubuntu-pwsh:latest --pull=false 2>&1 )"
  ACT_STATUS=$?

  {
    echo "######################################################################"
    echo "# ACT RESULT — CASE ${case}"
    echo "# command: act push --rm -P ubuntu-latest=act-ubuntu-pwsh:latest --pull=false"
    echo "# exit status: ${ACT_STATUS}"
    echo "######################################################################"
    echo "$ACT_OUTPUT"
    echo ""
  } >> "$ACT_RESULT"

  rm -rf "$work"
}

# Assert the summary line containing $1 carries exactly the integer $2.
assert_act_value() {
  local label="$1" want="$2" line got
  line="$(printf '%s\n' "$ACT_OUTPUT" | grep -F -- "$label" | head -1)"
  [ -n "$line" ] || { echo "label not found in act output: '$label'"; return 1; }
  got="$(printf '%s' "$line" | grep -oE '[0-9]+' | tail -1)"
  [ "$got" = "$want" ] || {
    echo "label '$label': expected '$want' got '$got' (line: '$line')"
    return 1
  }
}

# Assert both jobs reported success.
assert_jobs_succeeded() {
  local n
  n="$(printf '%s\n' "$ACT_OUTPUT" | grep -c "Job succeeded")"
  [ "$n" -ge 2 ] || { echo "expected >=2 'Job succeeded', got $n"; return 1; }
}

@test "act: case A — max-age policy, live mode (exact plan)" {
  run_case A
  [ "$ACT_STATUS" -eq 0 ]
  assert_jobs_succeeded
  [[ "$ACT_OUTPUT" == *"Mode: LIVE"* ]]
  assert_act_value "Total artifacts:" 4
  assert_act_value "Retained:"        2
  assert_act_value "Deleted:"         2
  assert_act_value "Space reclaimed:" 5000
  assert_act_value "Space retained:"  5000
  [[ "$ACT_OUTPUT" == *"Live run: 2 artifact(s) deleted."* ]]
  # The JSON plan step must also carry the matching values.
  [[ "$ACT_OUTPUT" == *'"deleted":2'* ]]
  [[ "$ACT_OUTPUT" == *'"space_reclaimed":5000'* ]]
}

@test "act: case B — max-age + keep-latest combined, live mode (exact plan)" {
  run_case B
  [ "$ACT_STATUS" -eq 0 ]
  assert_jobs_succeeded
  [[ "$ACT_OUTPUT" == *"Mode: LIVE"* ]]
  assert_act_value "Total artifacts:" 6
  assert_act_value "Deleted:"         3
  assert_act_value "Retained:"        3
  assert_act_value "Space reclaimed:" 1300
  assert_act_value "Space retained:"  800
  [[ "$ACT_OUTPUT" == *"Live run: 3 artifact(s) deleted."* ]]
  [[ "$ACT_OUTPUT" == *'"deleted":3'* ]]
  [[ "$ACT_OUTPUT" == *'"space_reclaimed":1300'* ]]
}

@test "act: case C — max-total-size budget, dry-run mode (exact plan)" {
  run_case C
  [ "$ACT_STATUS" -eq 0 ]
  assert_jobs_succeeded
  [[ "$ACT_OUTPUT" == *"Mode: DRY-RUN"* ]]
  assert_act_value "Total artifacts:" 3
  assert_act_value "Deleted:"         1
  assert_act_value "Retained:"        2
  assert_act_value "Space reclaimed:" 600
  assert_act_value "Space retained:"  800
  [[ "$ACT_OUTPUT" == *"Dry-run: no artifacts were deleted."* ]]
  [[ "$ACT_OUTPUT" == *'"mode":"dry-run"'* ]]
  [[ "$ACT_OUTPUT" == *'"deleted":1'* ]]
}

@test "act-result.txt artifact was produced and is non-empty" {
  [ -s "$ACT_RESULT" ]
  grep -q "ACT RESULT — CASE A" "$ACT_RESULT"
  grep -q "ACT RESULT — CASE B" "$ACT_RESULT"
  grep -q "ACT RESULT — CASE C" "$ACT_RESULT"
}
