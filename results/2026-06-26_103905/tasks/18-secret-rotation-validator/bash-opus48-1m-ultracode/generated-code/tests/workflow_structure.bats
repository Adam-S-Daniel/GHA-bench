#!/usr/bin/env bats
#
# Workflow structure tests: parse the GitHub Actions workflow YAML and assert it
# has the expected shape (triggers, jobs, steps, permissions, job dependencies),
# references the validator script/files that actually exist, and passes
# actionlint. These are fast and require no Docker/act.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    WF="$REPO_ROOT/.github/workflows/secret-rotation-validator.yml"
    SCRIPT="$REPO_ROOT/secret-rotation-validator.sh"
}

# Helper: run a python snippet against the parsed workflow. The snippet receives
# the parsed dict as `wf`. The `on:` key is parsed by PyYAML as the boolean True
# (YAML 1.1), so we normalize it back to wf['on'] for convenience.
wf_py() {
    python3 - "$WF" <<PY
import sys, yaml
with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)
# Normalize the YAML 1.1 'on' -> True quirk.
if True in wf and 'on' not in wf:
    wf['on'] = wf.pop(True)
$1
PY
}

@test "workflow file exists" {
    [ -f "$WF" ]
}

@test "workflow is valid YAML" {
    run wf_py "pass"
    [ "$status" -eq 0 ]
}

@test "workflow has a name" {
    run wf_py "assert wf['name'] == 'Secret Rotation Validator', wf['name']"
    [ "$status" -eq 0 ]
}

@test "workflow defines all four trigger events" {
    run wf_py "
on = wf['on']
for trig in ('push', 'pull_request', 'schedule', 'workflow_dispatch'):
    assert trig in on, 'missing trigger: ' + trig
"
    [ "$status" -eq 0 ]
}

@test "schedule trigger has a valid cron expression" {
    run wf_py "
sched = wf['on']['schedule']
assert isinstance(sched, list) and sched, 'schedule must be a non-empty list'
assert 'cron' in sched[0], 'schedule entry needs a cron key'
parts = sched[0]['cron'].split()
assert len(parts) == 5, 'cron must have 5 fields: ' + sched[0]['cron']
"
    [ "$status" -eq 0 ]
}

@test "workflow declares least-privilege permissions" {
    run wf_py "
perms = wf['permissions']
assert perms.get('contents') == 'read', perms
"
    [ "$status" -eq 0 ]
}

@test "workflow defines top-level env with config, reference date, warn days" {
    run wf_py "
env = wf['env']
for key in ('CONFIG_FILE', 'REFERENCE_DATE', 'WARN_DAYS'):
    assert key in env, 'missing env: ' + key
"
    [ "$status" -eq 0 ]
}

@test "workflow has both expected jobs" {
    run wf_py "
jobs = wf['jobs']
for j in ('lint-and-test', 'rotation-report'):
    assert j in jobs, 'missing job: ' + j
"
    [ "$status" -eq 0 ]
}

@test "rotation-report job depends on lint-and-test (job dependency)" {
    run wf_py "
needs = wf['jobs']['rotation-report']['needs']
needs = [needs] if isinstance(needs, str) else needs
assert 'lint-and-test' in needs, needs
"
    [ "$status" -eq 0 ]
}

@test "both jobs run on ubuntu-latest" {
    run wf_py "
for j in ('lint-and-test', 'rotation-report'):
    assert wf['jobs'][j]['runs-on'] == 'ubuntu-latest', j
"
    [ "$status" -eq 0 ]
}

@test "both jobs check out the repo with actions/checkout@v4" {
    run wf_py "
for j in ('lint-and-test', 'rotation-report'):
    steps = wf['jobs'][j]['steps']
    uses = [s.get('uses', '') for s in steps]
    assert any(u == 'actions/checkout@v4' for u in uses), (j, uses)
"
    [ "$status" -eq 0 ]
}

@test "workflow references the validator script by its real path" {
    # The script path must appear in the workflow AND exist on disk.
    grep -q "secret-rotation-validator.sh" "$WF"
    [ -f "$SCRIPT" ]
}

@test "workflow runs the bats unit tests via the real tests path" {
    grep -q "bats tests/validator.bats" "$WF"
    [ -f "$REPO_ROOT/tests/validator.bats" ]
}

@test "lint-and-test job runs shellcheck and bash -n" {
    run wf_py "
runs = ' '.join(s.get('run', '') for s in wf['jobs']['lint-and-test']['steps'])
assert 'shellcheck' in runs, 'no shellcheck step'
assert 'bash -n' in runs, 'no bash -n step'
"
    [ "$status" -eq 0 ]
}

@test "rotation-report produces both markdown and json output" {
    run wf_py "
runs = ' '.join(s.get('run', '') for s in wf['jobs']['rotation-report']['steps'])
assert '--format json' in runs, 'no json output step'
assert 'ROTATION-SUMMARY' in runs, 'no machine-readable summary line'
"
    [ "$status" -eq 0 ]
}

@test "actionlint passes on the workflow (exit 0)" {
    run actionlint "$WF"
    [ "$status" -eq 0 ]
}
