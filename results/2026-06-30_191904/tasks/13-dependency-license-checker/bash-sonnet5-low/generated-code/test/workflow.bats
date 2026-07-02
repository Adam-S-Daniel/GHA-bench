#!/usr/bin/env bats
# Tests that validate the GitHub Actions workflow itself: YAML structure,
# actionlint validation, and a full execution via `act push` in Docker.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WORKFLOW="$DIR/.github/workflows/dependency-license-checker.yml"
}

@test "workflow file exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares expected trigger events" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
triggers = doc.get(True) or doc.get('on')
print(' '.join(triggers.keys()))
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"pull_request"* ]]
  [[ "$output" == *"schedule"* ]]
  [[ "$output" == *"workflow_dispatch"* ]]
}

@test "workflow defines the test and license-check jobs with a dependency" {
  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
print(' '.join(doc['jobs'].keys()))
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test"* ]]
  [[ "$output" == *"license-check"* ]]

  run python3 -c "
import yaml
doc = yaml.safe_load(open('$WORKFLOW'))
print(doc['jobs']['license-check']['needs'])
"
  [ "$status" -eq 0 ]
  [ "$output" = "test" ]
}

@test "workflow references script and lib files that exist" {
  [ -f "$DIR/license_checker.sh" ]
  [ -f "$DIR/lib/manifest_parser.sh" ]
  [ -f "$DIR/lib/license_lookup.sh" ]
  run grep -c "license_checker.sh" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "workflow runs successfully end-to-end via act push" {
  local tmp
  tmp="$(mktemp -d)"
  cp -r "$DIR"/. "$tmp"/
  rm -rf "${tmp:?}/.git"
  cp "$DIR/.actrc" "$tmp/.actrc"

  (
    cd "$tmp" || exit 1
    git init -q
    git -c user.email="test@example.com" -c user.name="test" add -A
    git -c user.email="test@example.com" -c user.name="test" commit -q -m "test"
    act push --rm --pull=false
  ) > "$DIR/act-result.txt" 2>&1
  local act_status=$?

  [ -f "$DIR/act-result.txt" ]
  [ "$act_status" -eq 0 ]

  run cat "$DIR/act-result.txt"
  [[ "$output" == *"Job succeeded"* ]]
  [[ "$output" == *"requests,2.31.0,Apache-2.0,approved"* ]]
  [[ "$output" == *"flask,>=2.0.0,BSD-3-Clause,approved"* ]]
  [[ "$output" == *"mystery-pkg,0.1.0,UNKNOWN,unknown"* ]]
  [[ "$output" == *"ok 4 parse_manifest dispatches based on filename"* ]]
  [[ "$output" == *"16 tests"* ]] || [[ "$output" == *"1..16"* ]]

  rm -rf "$tmp"
}
