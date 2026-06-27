#!/usr/bin/env bats
#
# End-to-end pipeline tests: EVERY test case is executed through the GitHub
# Actions workflow via `act`, never against the script directly.
#
# To respect the "few act runs" budget (act is slow), the workflow processes
# all five fixture cases in a single push event using a build matrix, so one
# `act push` run produces every case's result. `setup_file` runs act exactly
# once, tees the full log to act-result.txt (the required artifact), and the
# individual @test cases assert on the exact, known-good value for each case.

setup_file() {
    PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_DIR
    export ACT_RESULT="${PROJECT_DIR}/act-result.txt"
    # Shared, per-file scratch that the @test bodies can also see.
    export ACT_OUT="${BATS_FILE_TMPDIR}/act.out"
    export ACT_EXIT_FILE="${BATS_FILE_TMPDIR}/act.exit"

    # --- assemble an isolated temp git repo with just our project files -----
    local work
    work="$(mktemp -d)"
    cp "${PROJECT_DIR}/label-assigner.sh" "${work}/"
    cp "${PROJECT_DIR}/label-rules.conf" "${work}/"
    cp -r "${PROJECT_DIR}/fixtures" "${work}/"
    mkdir -p "${work}/.github/workflows"
    cp "${PROJECT_DIR}/.github/workflows/pr-label-assigner.yml" "${work}/.github/workflows/"
    cp "${PROJECT_DIR}/.actrc" "${work}/" 2>/dev/null || true

    git -C "${work}" init -q
    git -C "${work}" add -A
    git -C "${work}" -c user.email=ci@example.com -c user.name=ci commit -q -m "init"

    # --- run the pipeline once via act (offline, local image) --------------
    (
        cd "${work}" || exit 1
        act push --rm --pull=false -P ubuntu-latest=act-ubuntu-pwsh:latest
    ) > "${ACT_OUT}" 2>&1
    printf '%s' "$?" > "${ACT_EXIT_FILE}"

    # --- persist the artifact (act-result.txt), clearly delimited ----------
    {
        echo "##############################################################"
        echo "# act push --rm  (single run, build matrix over all fixtures)"
        echo "# exit code: $(cat "${ACT_EXIT_FILE}")"
        echo "##############################################################"
        echo
        cat "${ACT_OUT}"
        echo
        echo "##############################################################"
        echo "# PER-CASE RESULTS (parsed from the run above)"
        echo "##############################################################"
        local fx
        for fx in docs-only api-tests mixed config-tie no-match; do
            echo "---------- TEST CASE: ${fx} ----------"
            grep -E "RESULT ${fx}:" "${ACT_OUT}" || echo "(no RESULT line found for ${fx})"
        done
    } > "${ACT_RESULT}"

    rm -rf "${work}"
}

# result_for <fixture>: echo the bracketed label set act produced for a case.
# e.g. "RESULT mixed: [api,dependencies]" -> "api,dependencies"
result_for() {
    local fx="$1" line
    line="$(grep -E "RESULT ${fx}:" "${ACT_OUT}" | head -n1)"
    # The act log prefixes each line with "[PR Label Assigner/...]", so strip
    # up to the LAST "[" (the value's opening bracket), then the trailing "]".
    line="${line##*\[}"
    line="${line%\]}"
    printf '%s' "$line"
}

@test "act exited 0 for the pipeline run" {
    [ "$(cat "${ACT_EXIT_FILE}")" -eq 0 ]
}

@test "act-result.txt artifact exists and is non-empty" {
    [ -f "${ACT_RESULT}" ]
    [ -s "${ACT_RESULT}" ]
}

@test "case docs-only: a docs/markdown PR -> documentation" {
    [ "$(result_for docs-only)" = "documentation" ]
}

@test "case api-tests: api source + test file -> tests,api,backend (priority order)" {
    [ "$(result_for api-tests)" = "tests,api,backend" ]
}

@test "case mixed: many areas -> api,dependencies,documentation,ci,backend" {
    [ "$(result_for mixed)" = "api,dependencies,documentation,ci,backend" ]
}

@test "case config-tie: equal-priority labels -> backend,config (alphabetical tie-break)" {
    [ "$(result_for config-tie)" = "backend,config" ]
}

@test "case no-match: unmatched files -> empty label set" {
    [ "$(result_for no-match)" = "" ]
}

@test "all five matrix jobs reported Job succeeded" {
    local fx
    for fx in docs-only api-tests mixed config-tie no-match; do
        # act labels matrix jobs "Assign labels-N"; the per-fixture RESULT
        # line confirms that fixture's job ran. Combined with the overall
        # succeeded count below, this proves each fixture succeeded.
        grep -qE "RESULT ${fx}:" "${ACT_OUT}"
    done
    # 5 matrix jobs + 1 summary job = 6 "Job succeeded" markers.
    run grep -c "Job succeeded" "${ACT_OUT}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 6 ]
}

@test "the summary job (needs: assign) ran and succeeded" {
    grep -qE "All label-assignment jobs completed successfully" "${ACT_OUT}"
    grep -qE "Summarize.*Job succeeded" "${ACT_OUT}"
}

@test "no job reported a failure" {
    run grep -E "Job failed" "${ACT_OUT}"
    [ "$status" -ne 0 ]   # grep finds nothing -> non-zero exit
}
