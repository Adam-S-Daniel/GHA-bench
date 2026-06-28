#!/usr/bin/env bats
#
# End-to-end CI harness: every test case is executed *through* the GitHub
# Actions workflow via `act` (nektos/act) — the script is never invoked
# directly here.
#
# For each case the harness:
#   1. builds an isolated temp git repo containing the project files plus that
#      case's fixture data (written to fixtures/ci-secrets.json, the path the
#      workflow audits),
#   2. runs `act push --rm`,
#   3. appends the full act output to act-result.txt (clearly delimited),
#   4. asserts act exited 0, that every job reports "Job succeeded", that the
#      in-pipeline bats unit suite passed, and that the rotation report
#      contains the EXACT expected metrics for that case's input.
#
# This file lives under test/act/ and is deliberately NOT part of test/unit/,
# so the workflow's `bats test/unit/` step never tries to run act inside act.
#
# NOTE: act is slow (~1-2 min/run). There are two cases here -> two act runs.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export PROJECT_ROOT
    export ACT_RESULT="${PROJECT_ROOT}/act-result.txt"
    # Force the locally-built act image so nothing is pulled from a registry.
    export ACT_IMAGE="act-ubuntu-pwsh:latest"
    # Start every full run with a fresh artifact file.
    {
        echo "############################################################"
        echo "# act-result.txt - GitHub Actions pipeline output via act  #"
        echo "# Workflow: .github/workflows/secret-rotation-validator.yml #"
        echo "############################################################"
    } > "$ACT_RESULT"
}

# run_act_case CASE_NAME FIXTURE_SRC
# Builds an isolated repo seeded with FIXTURE_SRC as the audited config, runs
# the workflow under act, and records the result in the globals ACT_RC/ACT_OUT.
run_act_case() {
    local case_name="$1" fixture_src="$2"
    local tmp; tmp="$(mktemp -d)"

    # Assemble a minimal but complete copy of the project.
    mkdir -p "$tmp/fixtures" "$tmp/test/unit" "$tmp/.github/workflows"
    cp "$PROJECT_ROOT/secret-rotation-validator.sh" "$tmp/"
    cp "$PROJECT_ROOT/.actrc" "$tmp/" 2>/dev/null || true
    cp "$PROJECT_ROOT"/fixtures/*.json "$tmp/fixtures/"
    cp "$PROJECT_ROOT"/test/unit/*.bats "$tmp/test/unit/"
    cp "$PROJECT_ROOT"/.github/workflows/*.yml "$tmp/.github/workflows/"

    # Seed this case's secrets as the file the workflow audits.
    cp "$fixture_src" "$tmp/fixtures/ci-secrets.json"

    # A committed git repo is what a real "push" pipeline sees.
    git -C "$tmp" init -q
    git -C "$tmp" add -A
    git -C "$tmp" -c user.email=ci@example.com -c user.name=ci commit -qm "case: $case_name"

    # Run the pipeline. Pin the platform image explicitly and disable pulling:
    # the image is built locally and has no registry to authenticate against.
    local out="$tmp/act.out"
    ( cd "$tmp" && act push --rm --pull=false -P "ubuntu-latest=${ACT_IMAGE}" ) >"$out" 2>&1
    ACT_RC=$?
    ACT_OUT="$(cat "$out")"

    # Persist the full output as the required artifact.
    {
        echo
        echo "================================================================"
        echo "=== CASE: ${case_name}   (act exit code: ${ACT_RC})"
        echo "=== fixture: ${fixture_src}"
        echo "================================================================"
        cat "$out"
    } >> "$ACT_RESULT"

    rm -rf "$tmp"
}

# Shared structural assertions every successful pipeline run must satisfy.
assert_pipeline_succeeded() {
    # act exited cleanly.
    [ "$ACT_RC" -eq 0 ]
    # All three jobs (lint, test, report) reported success.
    [ "$(grep -c 'Job succeeded' <<<"$ACT_OUT")" -ge 3 ]
    # The bats unit suite ran inside the pipeline (TAP plan line present) and
    # every test passed (no "not ok" lines). Count-agnostic so adding unit
    # tests never invalidates the harness.
    [[ "$ACT_OUT" =~ 1\.\.[0-9]+ ]]
    [[ "$ACT_OUT" != *"not ok"* ]]
}

@test "act/mixed: pipeline succeeds and reports exactly 2 expired / 1 warning / 1 ok" {
    run_act_case "mixed" "${PROJECT_ROOT}/fixtures/mixed.json"
    assert_pipeline_succeeded
    # Exact JSON-derived metrics surfaced by the report job.
    [[ "$ACT_OUT" == *"REPORT_EXPIRED=2"* ]]
    [[ "$ACT_OUT" == *"REPORT_WARNING=1"* ]]
    [[ "$ACT_OUT" == *"REPORT_OK=1"* ]]
    # Exact markdown summary rows.
    [[ "$ACT_OUT" == *"| Expired | 2 |"* ]]
    [[ "$ACT_OUT" == *"| Warning | 1 |"* ]]
    [[ "$ACT_OUT" == *"| OK | 1 |"* ]]
    # Exact per-secret row for the worst-overdue secret.
    [[ "$ACT_OUT" == *"| db-password | 2026-01-01 | 90 | 2026-04-01 | 88 | api, worker |"* ]]
}

@test "act/all-ok: pipeline succeeds and reports exactly 0 expired / 0 warning / 2 ok" {
    run_act_case "all-ok" "${PROJECT_ROOT}/fixtures/all-ok.json"
    assert_pipeline_succeeded
    [[ "$ACT_OUT" == *"REPORT_EXPIRED=0"* ]]
    [[ "$ACT_OUT" == *"REPORT_WARNING=0"* ]]
    [[ "$ACT_OUT" == *"REPORT_OK=2"* ]]
    [[ "$ACT_OUT" == *"| Expired | 0 |"* ]]
    [[ "$ACT_OUT" == *"| OK | 2 |"* ]]
}
