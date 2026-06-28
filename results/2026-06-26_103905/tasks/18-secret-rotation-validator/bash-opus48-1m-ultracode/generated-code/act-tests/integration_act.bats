#!/usr/bin/env bats
#
# Integration harness: drives the GitHub Actions workflow through `act`.
#
# Each @test is one fixture case. For every case the harness:
#   1. builds a throwaway git repo containing the project files + that case's
#      fixture data installed as fixtures/secrets.json (the path the workflow
#      reads),
#   2. runs `act push --rm`, capturing all output,
#   3. appends that output, clearly delimited, to act-result.txt in the repo
#      root (the current working directory),
#   4. asserts act exited 0, that every job reports "Job succeeded", and that
#      the report contains the EXACT expected values for that input.
#
# This file lives OUTSIDE tests/ on purpose: the CI workflow runs
# `bats tests/validator.bats`, so it never recurses into this act-in-act harness
# (which would require Docker-in-Docker). Run it explicitly:
#
#     bats act-tests/integration_act.bats
#
# NOTE: each @test performs one `act push` run (slow: ~1 min each).

setup_file() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export REPO_ROOT
    export ACT_RESULT="$REPO_ROOT/act-result.txt"
    # The custom image we want act to use. It exists locally; act must NOT try to
    # pull it from a registry (that fails with an auth error).
    export ACT_IMAGE="act-ubuntu-pwsh:latest"
    # NOTE: do not try to export a bash array here — arrays are not exported
    # across bats's per-test process boundary, so any array set in setup_file
    # arrives empty in the @test. Flags are passed inline in run_act_case().
    # Truncate the aggregate result file once for the whole harness run.
    : > "$ACT_RESULT"
}

# run_act_case CASE_NAME FIXTURE_FILE
# Builds a temp repo for the case, runs act, records output, and sets globals:
#   ACT_RC  (act exit code) and ACT_OUT (combined act stdout+stderr).
run_act_case() {
    local case_name="$1" fixture="$2"
    local workdir
    workdir="$(mktemp -d)"

    # --- assemble project files into the throwaway repo ---
    mkdir -p "$workdir/tests" "$workdir/fixtures" "$workdir/.github/workflows"
    cp "$REPO_ROOT/secret-rotation-validator.sh" "$workdir/"
    cp "$REPO_ROOT/tests/"*.bats "$workdir/tests/"
    cp "$REPO_ROOT/fixtures/"*.json "$workdir/fixtures/"
    cp "$REPO_ROOT/.github/workflows/"*.yml "$workdir/.github/workflows/"

    # Write a fresh .actrc that (a) maps ubuntu-latest to the local custom image
    # and (b) disables registry pulls. Putting --pull=false here guarantees it
    # applies regardless of CLI parsing quirks.
    printf -- '-P ubuntu-latest=%s\n--pull=false\n' "$ACT_IMAGE" > "$workdir/.actrc"

    # Install THIS case's fixture as the config the workflow consumes.
    cp "$REPO_ROOT/fixtures/$fixture" "$workdir/fixtures/secrets.json"

    # --- minimal git repo so actions/checkout has something to check out ---
    git -C "$workdir" init -q
    git -C "$workdir" -c user.email="harness@example.com" -c user.name="harness" add -A
    git -C "$workdir" -c user.email="harness@example.com" -c user.name="harness" \
        commit -qm "act case: $case_name"

    # --- run act, capturing combined output ---
    # Flags are passed inline (not via an exported array). The act call is in an
    # `if` so a non-zero exit does NOT abort this function under bats — we always
    # record output to act-result.txt and let the per-case assertions report.
    local out="$workdir/act.out"
    if ( cd "$workdir" && act push --rm --pull=false -P "ubuntu-latest=$ACT_IMAGE" ) > "$out" 2>&1; then
        ACT_RC=0
    else
        ACT_RC=$?
    fi
    ACT_OUT="$(cat "$out")"

    # --- append delimited output to the aggregate result file ---
    {
        echo "######################################################################"
        echo "# ACT TEST CASE: ${case_name}   (fixture=${fixture})"
        echo "######################################################################"
        cat "$out"
        echo "----------------------------------------------------------------------"
        echo "# END CASE ${case_name}: act exit code = ${ACT_RC}"
        echo "######################################################################"
        echo
    } >> "$ACT_RESULT"

    rm -rf "$workdir"
}

# Assert both jobs in the workflow reported success.
assert_all_jobs_succeeded() {
    local n
    n="$(grep -c "Job succeeded" <<<"$ACT_OUT" || true)"
    [ "$n" -ge 2 ] || {
        echo "expected >=2 'Job succeeded' (one per job), got $n" >&2
        return 1
    }
    # No job should have failed.
    ! grep -q "Job failed" <<<"$ACT_OUT"
}

@test "act/push: mixed fixture -> 1 expired, 1 warning, 1 ok" {
    run_act_case "mixed" "mixed.json"
    [ "$ACT_RC" -eq 0 ]
    assert_all_jobs_succeeded
    # Exact machine-readable summary line emitted by the workflow.
    [[ "$ACT_OUT" == *"ROTATION-SUMMARY expired=1 warning=1 ok=1 total=3"* ]]
    # Exact Markdown rows for each urgency class (act prefixes each stdout line,
    # so we match the row as a substring).
    [[ "$ACT_OUT" == *"| db-password | 2026-01-01 | 90 | 178 | -88 | api-service, worker |"* ]]
    [[ "$ACT_OUT" == *"| api-key | 2026-04-09 | 90 | 80 | 10 | gateway |"* ]]
    [[ "$ACT_OUT" == *"| tls-cert | 2026-06-01 | 365 | 27 | 338 | edge-proxy, cdn |"* ]]
    # Section headers prove grouping by urgency.
    [[ "$ACT_OUT" == *"## Expired (1)"* ]]
    [[ "$ACT_OUT" == *"## Warning (1)"* ]]
    [[ "$ACT_OUT" == *"## OK (1)"* ]]
}

@test "act/push: all-ok fixture -> 0 expired, 0 warning, 2 ok" {
    run_act_case "all-ok" "all-ok.json"
    [ "$ACT_RC" -eq 0 ]
    assert_all_jobs_succeeded
    [[ "$ACT_OUT" == *"ROTATION-SUMMARY expired=0 warning=0 ok=2 total=2"* ]]
    [[ "$ACT_OUT" == *"## Expired (0)"* ]]
    [[ "$ACT_OUT" == *"## OK (2)"* ]]
}

@test "act/push: all-expired fixture -> 2 expired, 0 warning, 0 ok" {
    run_act_case "all-expired" "all-expired.json"
    [ "$ACT_RC" -eq 0 ]
    assert_all_jobs_succeeded
    [[ "$ACT_OUT" == *"ROTATION-SUMMARY expired=2 warning=0 ok=0 total=2"* ]]
    [[ "$ACT_OUT" == *"## Expired (2)"* ]]
    [[ "$ACT_OUT" == *"| legacy-db-password | 2026-01-01 | 90 | 178 | -88 | billing, reports |"* ]]
}
