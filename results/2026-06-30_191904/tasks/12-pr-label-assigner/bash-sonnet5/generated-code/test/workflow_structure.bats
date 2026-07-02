#!/usr/bin/env bats
#
# Static structure tests for .github/workflows/pr-label-assigner.yml.
# These do NOT run the workflow (see workflow_act.bats for that); they
# parse the YAML and assert on triggers/jobs/steps, verify referenced
# script/fixture paths exist, and verify actionlint passes.

setup() {
  WORKFLOW="${BATS_TEST_DIRNAME}/../.github/workflows/pr-label-assigner.yml"
  PARSER="${BATS_TEST_DIRNAME}/helpers/parse_workflow.py"
  REPO_ROOT="${BATS_TEST_DIRNAME}/.."
}

@test "workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "workflow YAML parses successfully" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow declares push, pull_request, and workflow_dispatch triggers" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  triggers="$(echo "$output" | jq -r '.triggers | sort | join(",")')"
  [ "$triggers" = "pull_request,push,workflow_dispatch" ]
}

@test "workflow defines the assign-labels and report jobs" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  jobs="$(echo "$output" | jq -r '.jobs | sort | join(",")')"
  [ "$jobs" = "assign-labels,report" ]
}

@test "the report job depends on assign-labels (needs)" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  needs="$(echo "$output" | jq -r '.job_details.report.needs')"
  [ "$needs" = "assign-labels" ]
}

@test "the assign-labels job checks out the repo with actions/checkout@v4" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  uses="$(echo "$output" | jq -r '.job_details["assign-labels"].uses | join(",")')"
  [[ "$uses" == *"actions/checkout@v4"* ]]
}

@test "the workflow declares read contents and write pull-requests permissions" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  contents_perm="$(echo "$output" | jq -r '.permissions.contents')"
  pr_perm="$(echo "$output" | jq -r '.permissions["pull-requests"]')"
  [ "$contents_perm" = "read" ]
  [ "$pr_perm" = "write" ]
}

@test "the assign-labels job's run steps invoke label-assigner.sh" {
  run python3 "$PARSER" "$WORKFLOW"
  [ "$status" -eq 0 ]
  snippets="$(echo "$output" | jq -r '.job_details["assign-labels"].run_snippets | join("\n")')"
  [[ "$snippets" == *"label-assigner.sh"* ]]
}

@test "the script referenced by the workflow exists in the repo" {
  [ -f "$REPO_ROOT/label-assigner.sh" ]
  [ -x "$REPO_ROOT/label-assigner.sh" ]
}

@test "the default rules and changed-files fixture paths referenced by the workflow exist" {
  [ -f "$REPO_ROOT/rules.conf" ]
  [ -f "$REPO_ROOT/fixtures/changed-files.txt" ]
}

@test "actionlint passes on the workflow file" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
