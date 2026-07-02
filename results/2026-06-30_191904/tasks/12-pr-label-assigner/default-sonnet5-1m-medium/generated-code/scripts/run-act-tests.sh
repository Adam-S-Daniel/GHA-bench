#!/usr/bin/env bash
# Integration test harness: exercises PrLabelAssigner.ps1 end-to-end through
# the real GitHub Actions workflow, via `act push`, for every fixture case
# under fixtures/cases/. Per the task requirements, this is the ONLY place
# the pipeline is tested -- the script is never invoked directly here.
#
# For each case:
#   1. Build an isolated temp git repo containing the project files.
#   2. Overwrite fixtures/changed-files.json with that case's input.
#   3. Commit and run `act push --rm`.
#   4. Append the full act output to act-result.txt.
#   5. Assert act exited 0, both jobs report "Job succeeded", and the
#      computed label set exactly matches fixtures/cases/<case>/expected-labels.txt.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
CASES_DIR="$REPO_ROOT/fixtures/cases"

: > "$RESULT_FILE"

overall_status=0
case_count=0

for case_dir in "$CASES_DIR"/*/; do
    case_name="$(basename "$case_dir")"
    case_count=$((case_count + 1))
    changed_files_fixture="$case_dir/changed-files.json"
    expected_file="$case_dir/expected-labels.txt"

    if [[ ! -f "$changed_files_fixture" || ! -f "$expected_file" ]]; then
        echo "FAIL [$case_name]: missing fixture files" | tee -a "$RESULT_FILE"
        overall_status=1
        continue
    fi

    expected_labels="$(tr -d '[:space:]' < "$expected_file")"

    tmp_repo="$(mktemp -d)"

    # 1. Copy project files (script, tests, rules, workflow, fixtures, act config)
    #    into an isolated temp git repo -- this is the "PR" act will run against.
    cp -R "$REPO_ROOT/.github" "$tmp_repo/"
    cp "$REPO_ROOT/PrLabelAssigner.ps1" "$tmp_repo/"
    cp "$REPO_ROOT/PrLabelAssigner.Tests.ps1" "$tmp_repo/"
    cp "$REPO_ROOT/rules.json" "$tmp_repo/"
    cp "$REPO_ROOT/.actrc" "$tmp_repo/"
    cp -R "$REPO_ROOT/fixtures" "$tmp_repo/"

    # 2. This case's changed-files list becomes the canonical fixture the
    #    workflow reads by default.
    cp "$changed_files_fixture" "$tmp_repo/fixtures/changed-files.json"

    (
        cd "$tmp_repo" || exit 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Act Test Harness"
        git add -A
        git commit -q -m "test case: $case_name"
    )

    {
        echo "===== BEGIN CASE: $case_name ====="
        echo "--- changed files ---"
        cat "$changed_files_fixture"
        echo "--- expected labels: $expected_labels ---"
    } >> "$RESULT_FILE"

    # --pull=false: use the image already present locally (act-ubuntu-pwsh)
    # instead of force-pulling, which fails without registry credentials.
    act_output="$(cd "$tmp_repo" && act push --rm --pull=false 2>&1)"
    act_exit=$?

    {
        echo "$act_output"
        echo "===== act exit code: $act_exit ====="
        echo "===== END CASE: $case_name ====="
        echo
    } >> "$RESULT_FILE"

    case_ok=1

    if [[ $act_exit -ne 0 ]]; then
        echo "FAIL [$case_name]: act exited with code $act_exit (expected 0)"
        case_ok=0
    fi

    job_success_count="$(grep -c "Job succeeded" <<< "$act_output")"
    if [[ "$job_success_count" -lt 2 ]]; then
        echo "FAIL [$case_name]: expected 2 'Job succeeded' lines (test + assign-labels), got $job_success_count"
        case_ok=0
    fi

    actual_labels="$(grep -oE 'Labels: [^[:space:]]*|Labels: *$' <<< "$act_output" | tail -1 | sed -E 's/^Labels: ?//' | tr -d '[:space:]')"
    if [[ "$actual_labels" != "$expected_labels" ]]; then
        echo "FAIL [$case_name]: expected labels '$expected_labels', got '$actual_labels'"
        case_ok=0
    fi

    if [[ "$case_ok" -eq 1 ]]; then
        echo "PASS [$case_name]: labels='$actual_labels', act_exit=0, both jobs succeeded"
    else
        overall_status=1
    fi

    rm -rf "$tmp_repo"
done

echo
if [[ "$case_count" -eq 0 ]]; then
    echo "FAIL: no fixture cases found under $CASES_DIR"
    overall_status=1
fi

if [[ "$overall_status" -eq 0 ]]; then
    echo "All $case_count integration test case(s) passed. See $RESULT_FILE for full act output."
else
    echo "One or more integration test cases FAILED. See $RESULT_FILE for full act output."
fi

exit $overall_status
