#!/usr/bin/env bash
# Test harness: runs the GitHub Actions workflow via `act` for multiple
# fixture scenarios, in isolated temp git repos, and asserts on exact
# expected values parsed from the act output. Appends all output to
# act-result.txt (delimited per case) in the current working directory.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_FILE="$REPO_ROOT/act-result.txt"
: > "$RESULT_FILE"

FAIL=0

run_case() {
    local case_name="$1"
    local mutate_fn="$2"
    shift 2
    local -a expect_strings=("$@")

    echo "==================== CASE: $case_name ====================" >>"$RESULT_FILE"

    local tmprepo
    tmprepo="$(mktemp -d)"
    cp -r "$REPO_ROOT/.github" "$REPO_ROOT/aggregator.py" "$REPO_ROOT/tests" \
        "$REPO_ROOT/fixtures" "$REPO_ROOT/.actrc" "$tmprepo/"

    # apply case-specific mutation to the workflow copy, if any
    "$mutate_fn" "$tmprepo"

    (
        cd "$tmprepo" || exit 1
        git init -q
        git config user.email test@test.com
        git config user.name test
        git add -A
        git commit -q -m "init"
        act push --rm --pull=false
    ) >"$tmprepo/act-output.txt" 2>&1
    local act_exit=$?

    cat "$tmprepo/act-output.txt" >>"$RESULT_FILE"
    echo "act exit code: $act_exit" >>"$RESULT_FILE"

    if [ "$act_exit" -ne 0 ]; then
        echo "FAIL [$case_name]: act exited with $act_exit (expected 0)"
        FAIL=1
    fi

    if ! grep -q "\[Test Results Aggregator/Run aggregator unit tests\] 🏁  Job succeeded" "$tmprepo/act-output.txt"; then
        echo "FAIL [$case_name]: unit-tests job did not report 'Job succeeded'"
        FAIL=1
    fi
    if ! grep -q "\[Test Results Aggregator/Aggregate matrix test results\] 🏁  Job succeeded" "$tmprepo/act-output.txt"; then
        echo "FAIL [$case_name]: aggregate-results job did not report 'Job succeeded'"
        FAIL=1
    fi

    for expected in "${expect_strings[@]}"; do
        if ! grep -qF "$expected" "$tmprepo/act-output.txt"; then
            echo "FAIL [$case_name]: expected output not found: $expected"
            FAIL=1
        fi
    done

    rm -rf "$tmprepo"
}

no_mutation() { :; }

only_all_pass_fixture() {
    local repo="$1"
    # Point the aggregate step at a single, all-passing fixture file so the
    # expected totals for this case are deterministic and distinct from case 1.
    python3 - "$repo/.github/workflows/test-results-aggregator.yml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = """          python3 aggregator.py \\
            fixtures/junit/run1.xml \\
            fixtures/junit/run2.xml \\
            fixtures/json/run3.json \\
            --output summary.md"""
new = """          python3 aggregator.py \\
            fixtures/json/run_all_pass.json \\
            --output summary.md"""
assert old in content, "expected aggregator invocation not found in workflow"
content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
PYEOF
}

run_case "default-fixtures-with-failures" no_mutation \
    "| Total | 12 |" "| Passed | 6 |" "| Failed | 3 |" "| Skipped | 3 |" \
    "pkg.ModuleA::test_sub" "pkg.ModuleB::test_flaky" "20 passed in"

run_case "all-pass-fixture-only" only_all_pass_fixture \
    "| Total | 2 |" "| Passed | 2 |" "| Failed | 0 |" "| Skipped | 0 |" \
    "No flaky tests detected." "20 passed in"

echo "====================================================" >>"$RESULT_FILE"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL CASES PASSED" >>"$RESULT_FILE"
    echo "ALL CASES PASSED"
else
    echo "SOME CASES FAILED" >>"$RESULT_FILE"
    echo "SOME CASES FAILED"
fi

exit "$FAIL"
