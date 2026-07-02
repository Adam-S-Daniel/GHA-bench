#!/usr/bin/env bash
# Runs the PR Label Assigner workflow through `act` for a set of fixture
# scenarios, asserting on the exact expected label output for each one.
# All output is appended to act-result.txt in the project root.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$PROJECT_ROOT/act-result.txt"
: > "$RESULT_FILE"

OVERALL_STATUS=0

run_case() {
    local case_name="$1"
    local changed_files_content="$2"
    local expected_regex="$3"
    local not_expected_regex="${4:-}"

    echo "=== Test case: $case_name ===" | tee -a "$RESULT_FILE"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    # Copy project files (tracked by git) into an isolated temp repo.
    (cd "$PROJECT_ROOT" && git archive HEAD) | (cd "$tmp_dir" && tar -x)

    # Overwrite the scenario fixture file (the one the push-event default
    # path reads) with this test case's mocked changed-file list. This is
    # distinct from the fixture files the Pester unit tests depend on, so
    # scenario overwrites never break the CI test job.
    printf '%s\n' "$changed_files_content" > "$tmp_dir/fixtures/changed-files-scenario.txt"

    (
        cd "$tmp_dir" || exit 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test Runner"
        git add -A
        git commit -q -m "test case: $case_name"
        act push --rm --pull=false
    ) >"$tmp_dir/act.log" 2>&1
    local act_exit=$?

    cat "$tmp_dir/act.log" >> "$RESULT_FILE"
    echo "--- exit code: $act_exit ---" >> "$RESULT_FILE"

    if [ "$act_exit" -ne 0 ]; then
        echo "FAIL [$case_name]: act exited with code $act_exit" | tee -a "$RESULT_FILE"
        OVERALL_STATUS=1
        return
    fi

    local job_count
    job_count=$(grep -c "Job succeeded" "$tmp_dir/act.log")
    if [ "$job_count" -lt 2 ]; then
        echo "FAIL [$case_name]: expected 2 'Job succeeded' lines (test + assign-labels), got $job_count" | tee -a "$RESULT_FILE"
        OVERALL_STATUS=1
    fi

    if ! grep -qE "$expected_regex" "$tmp_dir/act.log"; then
        echo "FAIL [$case_name]: expected output matching '$expected_regex' not found" | tee -a "$RESULT_FILE"
        OVERALL_STATUS=1
    else
        echo "PASS [$case_name]: found expected output matching '$expected_regex'" | tee -a "$RESULT_FILE"
    fi

    if [ -n "$not_expected_regex" ] && grep -qE "$not_expected_regex" "$tmp_dir/act.log"; then
        echo "FAIL [$case_name]: unexpected output matching '$not_expected_regex' was found" | tee -a "$RESULT_FILE"
        OVERALL_STATUS=1
    fi

    echo "" >> "$RESULT_FILE"
}

# Case 1: docs-only changes -> exactly "documentation"
run_case "docs-only" \
    "docs/readme.md" \
    "Computed labels: documentation$"

# Case 2: api + test + docs changes -> api,documentation,tests (source loses to api)
run_case "mixed-api-tests-docs" \
    "src/api/handler.ps1
src/api/handler.test.ps1
docs/readme.md" \
    "Computed labels: (api,documentation,tests|api,tests,documentation|documentation,api,tests|documentation,tests,api|tests,api,documentation|tests,documentation,api)$" \
    "Computed labels:.*source"

# Case 3: plain src changes (no api subpath) -> exactly "source"
run_case "source-only" \
    "src/util/helpers.ps1" \
    "Computed labels: source$"

echo "=== Overall status: $OVERALL_STATUS ===" >> "$RESULT_FILE"
exit $OVERALL_STATUS
