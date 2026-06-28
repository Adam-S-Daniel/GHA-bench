#!/usr/bin/env bats
#
# Structural tests for the GitHub Actions workflow. These do NOT run act; they
# parse the YAML (via test/wf_query.py -> JSON, queried with jq), confirm the
# workflow references the script files that actually exist on disk, and assert
# that actionlint validates the workflow with exit code 0.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  WF="${ROOT}/.github/workflows/semantic-version-bumper.yml"
  # Cache the normalised JSON once per test.
  JSON="$(python3 "${ROOT}/test/wf_query.py" "$WF")"
}

# Helper: run a jq filter over the cached JSON.
jqf() {
  printf '%s' "$JSON" | jq -r "$1"
}

@test "workflow file exists" {
  [ -f "$WF" ]
}

@test "actionlint validates the workflow (exit 0)" {
  run actionlint "$WF"
  [ "$status" -eq 0 ]
}

@test "workflow YAML parses and has a name" {
  [ -n "$JSON" ]
  [ "$(jqf '.name')" = "Semantic Version Bumper" ]
}

@test "workflow declares push, pull_request, schedule and workflow_dispatch triggers" {
  run bash -c "printf '%s' '$JSON' | jq -e '.triggers | index(\"push\")'"
  [ "$status" -eq 0 ]
  printf '%s' "$JSON" | jq -e '.triggers | index("pull_request")'
  printf '%s' "$JSON" | jq -e '.triggers | index("schedule")'
  printf '%s' "$JSON" | jq -e '.triggers | index("workflow_dispatch")'
}

@test "schedule trigger has a valid cron expression" {
  cron="$(jqf '.on.schedule[0].cron')"
  [ "$cron" = "0 6 * * 1" ]
}

@test "workflow declares a permissions block" {
  [ "$(jqf '.permissions.contents')" = "read" ]
}

@test "workflow sets default env for version and commits files" {
  [ "$(jqf '.env.VERSION_FILE')" = "VERSION" ]
  [ "$(jqf '.env.COMMITS_FILE')" = "commits.txt" ]
  [ "$(jqf '.env.CHANGELOG_FILE')" = "CHANGELOG.md" ]
}

@test "workflow defines the bump and report jobs" {
  printf '%s' "$JSON" | jq -e '.jobs.bump'
  printf '%s' "$JSON" | jq -e '.jobs.report'
}

@test "report job depends on the bump job (job dependency)" {
  [ "$(jqf '.jobs.report.needs')" = "bump" ]
}

@test "bump job checks out the repo with actions/checkout@v4" {
  printf '%s' "$JSON" | jq -e '.jobs.bump.uses | index("actions/checkout@v4")'
}

@test "bump job exposes new_version and bump_type as outputs" {
  printf '%s' "$JSON" | jq -e '.jobs.bump.outputs.new_version'
  printf '%s' "$JSON" | jq -e '.jobs.bump.outputs.bump_type'
}

@test "bump job invokes the semantic-version-bumper.sh script" {
  printf '%s' "$JSON" | jq -e '.jobs.bump.runs | map(test("semantic-version-bumper\\.sh")) | any'
}

@test "report job consumes the bump job output" {
  printf '%s' "$JSON" | jq -e '.jobs.report.runs | map(test("needs.bump.outputs.new_version")) | any'
}

@test "the script referenced by the workflow exists on disk" {
  [ -f "${ROOT}/semantic-version-bumper.sh" ]
}

@test "the default version and commits fixture files referenced by the workflow exist" {
  [ -f "${ROOT}/VERSION" ]
  [ -f "${ROOT}/commits.txt" ]
}
