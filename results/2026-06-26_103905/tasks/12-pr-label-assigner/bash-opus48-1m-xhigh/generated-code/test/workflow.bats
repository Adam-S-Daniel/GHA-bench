#!/usr/bin/env bats
#
# End-to-end pipeline tests for the PR Label Assigner.
#
# Two layers live here:
#   1. Workflow STRUCTURE tests — parse the YAML, check triggers/jobs/steps,
#      confirm the workflow references the script files, and that actionlint
#      passes. These are fast and need no containers.
#   2. ACT INTEGRATION tests — every test case is fed to the real GitHub Actions
#      workflow through `act push --rm`. We never invoke the script directly
#      here: all behaviour is observed through the pipeline. Each run's full
#      output is appended to act-result.txt, and we assert on exact label values
#      plus "Job succeeded" for every job.

setup_file() {
    PROJECT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # Fresh act-result.txt for this run; each act case appends to it.
    : >"$PROJECT/act-result.txt"
}

setup() {
    PROJECT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF="$PROJECT/.github/workflows/pr-label-assigner.yml"
    SCRIPT="$PROJECT/pr-label-assigner.sh"
    CONFIG="$PROJECT/labels.config"
    ACT_RESULT="$PROJECT/act-result.txt"
}

# --- helpers -----------------------------------------------------------------

# py_assert SNIPPET — run a python check against the workflow YAML. The snippet
# may use the pre-loaded `wf` dict; it must raise/AssertionError to fail.
py_assert() {
    python3 - "$WF" <<PY
import sys, yaml
with open(sys.argv[1]) as fh:
    wf = yaml.safe_load(fh)
$1
print("ok")
PY
}

# _run_act_case NAME EXPECTED_CSV FIXTURE — build an isolated git repo with the
# project files + this case's changed-files fixture, run the workflow under act,
# append the output to act-result.txt, and stash status/output in globals.
_run_act_case() {
    local name="$1" expected_csv="$2" fixture="$3"
    local dir
    dir="$(mktemp -d)"

    # Assemble the throwaway project.
    cp "$SCRIPT" "$CONFIG" "$PROJECT/.actrc" "$dir/"
    mkdir -p "$dir/.github/workflows" "$dir/fixtures"
    cp "$WF" "$dir/.github/workflows/pr-label-assigner.yml"
    printf '%s' "$fixture" >"$dir/fixtures/changed-files.txt"

    # A committed repo is required for actions/checkout@v4.
    git -C "$dir" init -q
    git -C "$dir" config user.email "tester@example.com"
    git -C "$dir" config user.name "tester"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "case: $name"

    # Run the pipeline. `run` keeps a non-zero exit from failing the test so we
    # can assert on it ourselves.
    # --pull=false: the act image is built locally, so never force-pull it.
    run env DIR="$dir" bash -c 'cd "$DIR" && NO_COLOR=1 act push --rm --pull=false 2>&1'
    ACT_STATUS="$status"
    ACT_OUTPUT="$output"

    {
        echo "############################################################"
        echo "# TEST CASE: $name"
        echo "# changed files:"
        printf '%s\n' "$fixture" | sed 's/^/#   /'
        echo "# expected labels (CSV): [$expected_csv]"
        echo "# act exit code: $ACT_STATUS"
        echo "############################################################"
        printf '%s\n' "$ACT_OUTPUT"
        echo ""
    } >>"$ACT_RESULT"

    rm -rf "$dir"
}

# _assert_csv EXPECTED — pull the PRLABELS::...::END marker out of the act log
# and compare against the exact expected comma-separated label list.
_assert_csv() {
    local expected="$1" line v
    line="$(printf '%s\n' "$ACT_OUTPUT" | grep 'PRLABELS::' | tail -1)"
    [ -n "$line" ] || {
        echo "PRLABELS marker not found in act output"
        return 1
    }
    v="${line#*PRLABELS::}"
    v="${v%%::END*}"
    v="${v%$'\r'}"
    [ "$v" = "$expected" ] || {
        echo "label CSV mismatch: got [$v] expected [$expected]"
        return 1
    }
}

# _assert_all_jobs_succeeded — the workflow has two jobs; both must succeed.
_assert_all_jobs_succeeded() {
    local n
    n="$(printf '%s\n' "$ACT_OUTPUT" | grep -c 'Job succeeded' || true)"
    [ "$n" -eq 2 ] || {
        echo "expected 2 'Job succeeded' lines, found $n"
        return 1
    }
    if printf '%s\n' "$ACT_OUTPUT" | grep -q 'Job failed'; then
        echo "found a 'Job failed' line"
        return 1
    fi
}

# === STRUCTURE TESTS =========================================================

@test "structure: workflow passes actionlint" {
    run actionlint "$WF"
    [ "$status" -eq 0 ]
}

@test "structure: declares push, pull_request and workflow_dispatch triggers" {
    run py_assert '
on = wf.get(True, wf.get("on"))
assert isinstance(on, dict), f"on is not a mapping: {on!r}"
for trig in ("push", "pull_request", "workflow_dispatch"):
    assert trig in on, f"missing trigger: {trig}"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "structure: defines validate and assign-labels jobs with a dependency" {
    run py_assert '
jobs = wf["jobs"]
assert "validate" in jobs, "missing validate job"
assert "assign-labels" in jobs, "missing assign-labels job"
needs = jobs["assign-labels"].get("needs")
needs = [needs] if isinstance(needs, str) else (needs or [])
assert "validate" in needs, f"assign-labels must need validate, got {needs}"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "structure: declares permissions and runs on ubuntu-latest" {
    run py_assert '
assert "permissions" in wf, "missing top-level permissions"
for name, job in wf["jobs"].items():
    ro = job.get("runs-on")
    assert ro == "ubuntu-latest", name + " runs-on=" + str(ro)
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "structure: every job checks out and every run step uses bash" {
    run py_assert '
for name, job in wf["jobs"].items():
    steps = job["steps"]
    assert any("checkout" in (s.get("uses") or "") for s in steps), f"{name}: no checkout"
    for s in steps:
        if "run" in s:
            assert s.get("shell") == "bash", f"{name}: run step not using bash"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "structure: workflow references the script and config, and they exist" {
    grep -q "pr-label-assigner.sh" "$WF"
    grep -q "labels.config" "$WF"
    [ -f "$SCRIPT" ]
    [ -f "$CONFIG" ]
}

# === ACT INTEGRATION TESTS ===================================================

@test "act: mixed change set produces the full prioritized label list" {
    local fixture
    fixture="$(printf '%s\n' \
        "docs/guide/setup.md" \
        "src/api/users.js" \
        "src/api/users.test.js" \
        "src/utils/helpers.js" \
        "README.md")"
    _run_act_case "mixed" "tests,api,backend,documentation,source" "$fixture"
    [ "$ACT_STATUS" -eq 0 ]
    _assert_csv "tests,api,backend,documentation,source"
    _assert_all_jobs_succeeded
}

@test "act: ci + test files map to deduped, prioritized labels" {
    local fixture
    fixture="$(printf '%s\n' \
        ".github/workflows/build.yml" \
        "lib/widget.test.ts" \
        "config/app.yaml")"
    _run_act_case "ci-and-tests" "tests,ci" "$fixture"
    [ "$ACT_STATUS" -eq 0 ]
    _assert_csv "tests,ci"
    _assert_all_jobs_succeeded
}

@test "act: a change set matching no rule yields an empty label set" {
    local fixture
    fixture="$(printf '%s\n' "LICENSE" "Makefile")"
    _run_act_case "no-match" "" "$fixture"
    [ "$ACT_STATUS" -eq 0 ]
    _assert_csv ""
    _assert_all_jobs_succeeded
}
