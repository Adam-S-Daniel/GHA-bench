#!/usr/bin/env bats
# Structure tests for the GitHub Actions workflow: parse the YAML and assert
# on triggers/jobs/steps, confirm the workflow references real files, and
# confirm actionlint passes. These run on the host (not through act) since
# they're static checks of the workflow file itself.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    WORKFLOW="$SCRIPT_DIR/.github/workflows/semantic-version-bumper.yml"
}

@test "workflow file exists" {
    [ -f "$WORKFLOW" ]
}

@test "workflow YAML parses and declares expected triggers" {
    run python3 -c "
import yaml, sys
with open('$WORKFLOW') as f:
    doc = yaml.safe_load(f)
# YAML parses 'on:' as boolean True key under some loaders; handle both.
triggers = doc.get('on', doc.get(True))
assert 'push' in triggers, 'missing push trigger'
assert 'pull_request' in triggers, 'missing pull_request trigger'
assert 'workflow_dispatch' in triggers, 'missing workflow_dispatch trigger'
assert 'schedule' in triggers, 'missing schedule trigger'
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow declares the test and bump jobs with a dependency between them" {
    run python3 -c "
import yaml
with open('$WORKFLOW') as f:
    doc = yaml.safe_load(f)
jobs = doc['jobs']
assert 'test' in jobs, 'missing test job'
assert 'bump' in jobs, 'missing bump job'
assert jobs['bump']['needs'] == 'test', 'bump job must depend on test job'
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "workflow references bump-version.sh and the bats test file, and those files exist" {
    run python3 -c "
import yaml
with open('$WORKFLOW') as f:
    doc = yaml.safe_load(f)
jobs = doc['jobs']
test_steps = [s.get('run', '') for s in jobs['test']['steps']]
bump_steps = [s.get('run', '') for s in jobs['bump']['steps']]
assert any('test/version_bumper.bats' in s for s in test_steps), 'test job does not run the bats suite'
assert any('bump-version.sh' in s for s in bump_steps), 'bump job does not invoke bump-version.sh'
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
    [ -f "$SCRIPT_DIR/bump-version.sh" ]
    [ -f "$SCRIPT_DIR/test/version_bumper.bats" ]
}

@test "workflow declares read-only top-level permissions" {
    run python3 -c "
import yaml
with open('$WORKFLOW') as f:
    doc = yaml.safe_load(f)
assert doc['permissions']['contents'] == 'read'
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "actionlint passes on the workflow file" {
    run actionlint "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
