#!/usr/bin/env bash
# Shared helpers for the semantic-version-bumper bats suite.
#
# Per the task spec, every functional test case must exercise the real
# GitHub Actions workflow through `act` — the script is never invoked
# directly in this suite. Each case gets its own throwaway git repo so
# runs can't leak state into one another.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
ACT_RESULT_FILE="${PROJECT_ROOT}/act-result.txt"

# run_pipeline_case NAME START_VERSION COMMITS_FIXTURE
#
# Builds an isolated temp git repo containing the project's workflow,
# script, and this case's fixture data (a mock commit log + starting
# VERSION), commits it, and runs `act push --rm` against it. Appends the
# full act output to ACT_RESULT_FILE under a clear delimiter and leaves
# bats' $status/$output populated for the caller's assertions.
run_pipeline_case() {
    local case_name=$1 start_version=$2 commits_fixture=$3
    local workdir
    workdir="$(mktemp -d)"

    cp "${PROJECT_ROOT}/bump_version.sh" "$workdir/"
    cp "${PROJECT_ROOT}/.actrc" "$workdir/"
    cp -r "${PROJECT_ROOT}/.github" "$workdir/"
    cp "${PROJECT_ROOT}/fixtures/${commits_fixture}" "$workdir/COMMITS.txt"
    printf '%s\n' "$start_version" > "$workdir/VERSION"

    (
        cd "$workdir" || exit 1
        git init -q -b main
        git -c user.email=test@example.com -c user.name="Bats CI" add -A
        git -c user.email=test@example.com -c user.name="Bats CI" commit -q -m "chore: seed ${case_name} fixture"
    )

    run bash -c "cd '${workdir}' && exec timeout 150 act push --rm --pull=false --action-offline-mode"

    # shellcheck disable=SC2154  # $output/$status are set by bats' `run` above
    {
        echo "===== TEST CASE: ${case_name} (start=${start_version}, fixture=${commits_fixture}) ====="
        echo "$output"
        echo "----- exit status: ${status} -----"
        echo
    } >> "$ACT_RESULT_FILE"

    rm -rf "$workdir"
}
