#!/usr/bin/env bats
#
# Test suite for the test-results aggregator.
#
# Per the task requirements, ALL functional test cases execute through the
# GitHub Actions workflow via `act`. `setup_file` runs the workflow exactly
# once (act is expensive), captures the full output to act-result.txt, and the
# individual @test cases assert on EXACT expected values parsed from that
# known-good run. Workflow-structure tests (YAML parse, script-path
# references, actionlint) run directly since they don't need a container.
#
# Expected known-good results for the committed fixtures
# (fixtures/run1.xml + fixtures/run2.json):
#   passed=5 failed=2 skipped=1 total=8 duration=4.20s
#   flaky tests: test_logout, test_payment
#
# Red/green TDD note: each assertion below was written before the
# corresponding script/workflow behavior existed, watched fail, then made to
# pass with the minimum implementation, then refactored.

PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WORKFLOW="${PROJECT_DIR}/.github/workflows/test-results-aggregator.yml"
ACT_RESULT="${PROJECT_DIR}/act-result.txt"

# --- One-time workflow execution via act -----------------------------------
setup_file() {
	export PROJECT_DIR WORKFLOW ACT_RESULT
	# Fresh artifact each run.
	: >"${ACT_RESULT}"

	# Build an isolated temp git repo containing only the project deliverables,
	# exactly as a clean checkout would look.
	local tmp
	tmp="$(mktemp -d)"
	export ACT_TMP="${tmp}"

	cp "${PROJECT_DIR}/aggregate.sh" "${tmp}/"
	cp -r "${PROJECT_DIR}/fixtures" "${tmp}/"
	mkdir -p "${tmp}/.github/workflows"
	cp "${WORKFLOW}" "${tmp}/.github/workflows/"
	# Carry the .actrc so act selects the pre-built container image.
	[ -f "${PROJECT_DIR}/.actrc" ] && cp "${PROJECT_DIR}/.actrc" "${tmp}/"

	(
		cd "${tmp}"
		git init -q
		git config user.email "test@example.com"
		git config user.name "bats"
		git add -A
		git commit -qm "test"
	)

	{
		echo "============================================================"
		echo "ACT CASE: matrix-build (fixtures/run1.xml + fixtures/run2.json)"
		echo "============================================================"
	} >>"${ACT_RESULT}"

	# Run the workflow; never let a non-zero exit abort setup_file so the
	# dedicated exit-code test can report it cleanly.
	local exit_code=0
	# --pull=false: the act container image is built locally, so disable act's
	# default force-pull (it would otherwise try a registry pull and fail).
	( cd "${tmp}" && act push --rm --pull=false ) >"${tmp}/act.out" 2>&1 || exit_code=$?
	cat "${tmp}/act.out" >>"${ACT_RESULT}"
	echo "ACT_EXIT_CODE=${exit_code}" >>"${ACT_RESULT}"
	export ACT_EXIT_CODE="${exit_code}"
}

teardown_file() {
	[ -n "${ACT_TMP:-}" ] && rm -rf "${ACT_TMP}"
}

# ===========================================================================
# Functional tests — assert on the act output (act-result.txt)
# ===========================================================================

@test "act-result.txt artifact exists and is non-empty" {
	[ -s "${ACT_RESULT}" ]
}

@test "act exited with code 0" {
	[ "${ACT_EXIT_CODE}" -eq 0 ]
}

@test "both jobs report 'Job succeeded'" {
	# Two jobs: aggregate + verify.
	run grep -c "Job succeeded" "${ACT_RESULT}"
	[ "${output}" -ge 2 ]
}

@test "aggregate job ran" {
	grep -qF "Aggregate test results" "${ACT_RESULT}"
}

@test "verify job ran" {
	grep -qF "Verify aggregated totals" "${ACT_RESULT}"
}

@test "summary reports exactly 5 passed" {
	grep -qF "| Passed | 5 |" "${ACT_RESULT}"
}

@test "summary reports exactly 2 failed" {
	grep -qF "| Failed | 2 |" "${ACT_RESULT}"
}

@test "summary reports exactly 1 skipped" {
	grep -qF "| Skipped | 1 |" "${ACT_RESULT}"
}

@test "summary reports exactly 8 total" {
	grep -qF "| Total | 8 |" "${ACT_RESULT}"
}

@test "summary reports exactly 4.20s duration" {
	grep -qF "| Duration | 4.20s |" "${ACT_RESULT}"
}

@test "summary lists test_logout as flaky" {
	grep -qF -- "- test_logout" "${ACT_RESULT}"
}

@test "summary lists test_payment as flaky" {
	grep -qF -- "- test_payment" "${ACT_RESULT}"
}

@test "summary detects exactly 2 flaky tests" {
	grep -qF "Detected 2 flaky test(s)" "${ACT_RESULT}"
}

@test "overall result line is FAILED (failures present)" {
	grep -qF "**Result: FAILED**" "${ACT_RESULT}"
}

@test "verify job confirmed all totals" {
	grep -qF "All aggregated totals verified." "${ACT_RESULT}"
}

@test "verify job asserted exact passed output" {
	grep -qF "OK   passed: 5" "${ACT_RESULT}"
}

@test "verify job asserted exact flaky output" {
	grep -qF "OK   flaky: test_logout,test_payment" "${ACT_RESULT}"
}

# ===========================================================================
# Workflow-structure tests — parse YAML / verify references / actionlint
# ===========================================================================

@test "workflow file exists" {
	[ -f "${WORKFLOW}" ]
}

@test "workflow YAML parses and has expected triggers" {
	run python3 - "${WORKFLOW}" <<-'PY'
		import sys, yaml
		with open(sys.argv[1]) as f:
		    wf = yaml.safe_load(f)
		# PyYAML parses the bare `on:` key as boolean True.
		on = wf.get("on", wf.get(True))
		for trig in ("push", "pull_request", "schedule", "workflow_dispatch"):
		    assert trig in on, f"missing trigger: {trig}"
		print("triggers-ok")
	PY
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"triggers-ok"* ]]
}

@test "workflow has aggregate and verify jobs with a dependency" {
	run python3 - "${WORKFLOW}" <<-'PY'
		import sys, yaml
		wf = yaml.safe_load(open(sys.argv[1]))
		jobs = wf["jobs"]
		assert "aggregate" in jobs, "missing aggregate job"
		assert "verify" in jobs, "missing verify job"
		assert jobs["verify"]["needs"] == "aggregate", "verify must need aggregate"
		assert wf["permissions"]["contents"] == "read", "expected least-privilege perms"
		assert "FIXTURES" in wf["env"], "expected FIXTURES env var"
		print("jobs-ok")
	PY
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"jobs-ok"* ]]
}

@test "workflow steps use checkout and reference aggregate.sh" {
	run python3 - "${WORKFLOW}" <<-'PY'
		import sys, yaml
		wf = yaml.safe_load(open(sys.argv[1]))
		steps = wf["jobs"]["aggregate"]["steps"]
		uses = [s.get("uses", "") for s in steps]
		assert any(u.startswith("actions/checkout@v4") for u in uses), "missing checkout@v4"
		runs = " ".join(s.get("run", "") for s in steps)
		assert "aggregate.sh" in runs, "workflow does not invoke aggregate.sh"
		print("steps-ok")
	PY
	[ "${status}" -eq 0 ]
	[[ "${output}" == *"steps-ok"* ]]
}

@test "script files referenced by the workflow exist on disk" {
	[ -f "${PROJECT_DIR}/aggregate.sh" ]
	[ -f "${PROJECT_DIR}/fixtures/run1.xml" ]
	[ -f "${PROJECT_DIR}/fixtures/run2.json" ]
}

@test "actionlint passes with exit code 0" {
	run actionlint "${WORKFLOW}"
	[ "${status}" -eq 0 ]
}

@test "aggregate.sh passes bash -n syntax check" {
	run bash -n "${PROJECT_DIR}/aggregate.sh"
	[ "${status}" -eq 0 ]
}

@test "aggregate.sh passes shellcheck" {
	run shellcheck "${PROJECT_DIR}/aggregate.sh"
	[ "${status}" -eq 0 ]
}
