#!/usr/bin/env bats
# Integration tests: every test case actually runs the real GitHub Actions
# workflow via `act push --rm` in an isolated temp git repo (not by calling
# bump-version.sh directly). Output is captured and appended to
# act-result.txt, and each case's output is asserted against its exact
# expected version.

setup_file() {
    export PROJECT_DIR
    PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export RESULT_FILE="$PROJECT_DIR/act-result.txt"
    : > "$RESULT_FILE"
}

# run_case CASE_NAME VERSION_CONTENT COMMITS_FIXTURE
# Builds an isolated temp git repo containing the project files plus the
# given fixture data, runs the workflow with `act push --rm`, and appends
# the full output to act-result.txt under a clearly delimited section.
run_case() {
    local case_name="$1"
    local version_content="$2"
    local commits_fixture="$3"

    local work_dir
    work_dir="$(mktemp -d)"

    cp "$PROJECT_DIR/bump-version.sh" "$work_dir/"
    cp -r "$PROJECT_DIR/.github" "$work_dir/"
    cp -r "$PROJECT_DIR/test" "$work_dir/"
    cp "$PROJECT_DIR/.actrc" "$work_dir/"
    echo "$version_content" > "$work_dir/VERSION"
    cp "$PROJECT_DIR/test/fixtures/$commits_fixture" "$work_dir/commits.txt"

    (
        set +e
        cd "$work_dir" || exit 1
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test Runner"
        git add -A
        git commit -q -m "test fixture: $case_name"
        act push --rm --pull=false
        echo $? > "$work_dir/act-exit-code.txt"
    ) > "$work_dir/act-output.txt" 2>&1
    local act_status
    act_status="$(cat "$work_dir/act-exit-code.txt" 2>/dev/null || echo 1)"

    {
        echo "===== CASE: $case_name ====="
        cat "$work_dir/act-output.txt"
        echo "===== END CASE: $case_name (exit=$act_status) ====="
        echo ""
    } >> "$RESULT_FILE"

    ACT_STATUS=$act_status
    ACT_OUTPUT="$(cat "$work_dir/act-output.txt")"
    rm -rf "$work_dir"
}

@test "act: patch bump case (fix-only commits) yields exact version 1.4.3" {
    run_case "patch" "1.4.2" "commits-patch.txt"
    [ "$ACT_STATUS" -eq 0 ]
    [[ "$ACT_OUTPUT" == *"Bumped to: 1.4.3"* ]]
    [[ "$ACT_OUTPUT" != *"Bumped to: 1.4.4"* ]]
    grep -q "Job succeeded" <<< "$ACT_OUTPUT"
}

@test "act: minor bump case (feat commit present) yields exact version 1.5.0" {
    run_case "minor" "1.4.2" "commits-minor.txt"
    [ "$ACT_STATUS" -eq 0 ]
    [[ "$ACT_OUTPUT" == *"Bumped to: 1.5.0"* ]]
    grep -q "Job succeeded" <<< "$ACT_OUTPUT"
}

@test "act: major bump case (breaking change marker) yields exact version 2.0.0" {
    run_case "major" "1.4.2" "commits-major.txt"
    [ "$ACT_STATUS" -eq 0 ]
    [[ "$ACT_OUTPUT" == *"Bumped to: 2.0.0"* ]]
    grep -q "Job succeeded" <<< "$ACT_OUTPUT"
}

@test "act-result.txt was produced and contains all three cases" {
    [ -f "$RESULT_FILE" ]
    grep -q "CASE: patch" "$RESULT_FILE"
    grep -q "CASE: minor" "$RESULT_FILE"
    grep -q "CASE: major" "$RESULT_FILE"
}
