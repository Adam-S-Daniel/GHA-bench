#!/usr/bin/env bats
#
# workflow.bats
# -------------
# End-to-end tests. EVERY assertion is made against output produced by running
# the GitHub Actions workflow through `act` -- the script is never invoked
# directly here. The workflow uses a fixture matrix (mixed / docs-only / none),
# so a single `act push` run exercises all test cases at once; this keeps us
# well within the act-run budget while still asserting exact, known-good label
# sets for each fixture.
#
# setup_file() runs act once, captures the full combined output, appends it to
# act-result.txt (the required artifact), and stashes the exit code. Each @test
# then asserts on that shared capture.

PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
ACT_OUT="${BATS_FILE_TMPDIR}/act-output.txt"
ACT_RC="${BATS_FILE_TMPDIR}/act-rc.txt"
RESULT_FILE="${PROJECT_DIR}/act-result.txt"

setup_file() {
    # Build an isolated temp git repo containing the project files. act needs a
    # git repository with the workflow + script + fixtures checked in.
    local repo="${BATS_FILE_TMPDIR}/repo"
    mkdir -p "${repo}"
    cp -r \
        "${PROJECT_DIR}/.github" \
        "${PROJECT_DIR}/label-assigner.sh" \
        "${PROJECT_DIR}/rules.conf" \
        "${PROJECT_DIR}/fixtures" \
        "${PROJECT_DIR}/.actrc" \
        "${repo}/"

    (
        cd "${repo}"
        git init -q
        git config user.email "ci@example.com"
        git config user.name "CI"
        git add -A
        git commit -q -m "fixture commit"
    )

    # Run the workflow via act. --rm cleans up containers; --pull=false avoids
    # network image pulls (the custom act image already exists locally).
    set +e
    ( cd "${repo}" && act push --rm --pull=false ) >"${ACT_OUT}" 2>&1
    echo "$?" >"${ACT_RC}"
    set -e

    # Persist the captured output to the required artifact, clearly delimited.
    {
        echo "==================== act push (fixture matrix) ===================="
        echo "# exit code: $(cat "${ACT_RC}")"
        echo "-------------------------------------------------------------------"
        cat "${ACT_OUT}"
        echo "==================== end act push ================================="
        echo
    } >>"${RESULT_FILE}"
}

# --- act execution health --------------------------------------------------

@test "act exited with code 0" {
    run cat "${ACT_RC}"
    [ "${output}" = "0" ]
}

@test "every job reports Job succeeded (lint + 3 matrix jobs = 4)" {
    local count
    count="$(grep -c 'Job succeeded' "${ACT_OUT}" || true)"
    [ "${count}" -ge 4 ]
}

@test "lint job ran (bash syntax check)" {
    grep -q 'Bash syntax check' "${ACT_OUT}"
}

# --- exact expected label sets per fixture ---------------------------------

@test "fixture 'mixed' yields exactly tests,documentation,api,backend" {
    grep -q 'RESULT fixture=mixed got=\[LABELS: tests,documentation,api,backend\] want=\[LABELS: tests,documentation,api,backend\]' "${ACT_OUT}"
    grep -q 'ASSERT-OK fixture=mixed' "${ACT_OUT}"
}

@test "fixture 'docs-only' yields exactly documentation" {
    grep -q 'RESULT fixture=docs-only got=\[LABELS: documentation\] want=\[LABELS: documentation\]' "${ACT_OUT}"
    grep -q 'ASSERT-OK fixture=docs-only' "${ACT_OUT}"
}

@test "fixture 'none' yields an empty label set" {
    grep -q 'RESULT fixture=none got=\[LABELS:\] want=\[LABELS:\]' "${ACT_OUT}"
    grep -q 'ASSERT-OK fixture=none' "${ACT_OUT}"
}

@test "no fixture produced an assertion failure" {
    ! grep -q 'ASSERT-FAIL' "${ACT_OUT}"
}
