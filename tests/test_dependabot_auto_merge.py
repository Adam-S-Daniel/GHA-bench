"""Structural + behavioural guards on .github/workflows/dependabot-auto-merge.yml.

Why this file exists: cms-platform#437
(https://github.com/Adam-S-Daniel/cms-platform/issues/437) found that
`gh pr merge --auto --merge "$PR_URL" || true` in this workflow's `auto-merge`
job did not no-op the way its header claimed. `gh` treats a PR with
mergeStateStatus CLEAN/HAS_HOOKS/UNSTABLE as already mergeable
(`isImmediatelyMergeable` in cli/cli's pkg/cmd/pr/merge/merge.go) and merges
it immediately rather than arming native auto-merge to wait -- so on a repo
with no required status checks (this one), Dependabot PRs merged before their
own CI had even reported. GHA-bench#75 is the local instance: merged
18:58:30Z, its `test` check finished 18:58:59Z. The fix has two halves: job
`auto-merge` never attempts a merge again (it only enforces the manifest-path
allowlist), and job `sweep`'s scheduled merge -- the only unattended merge
path left -- gates on the WHOLE statusCheckRollup being green, requires at
least one of those checks to come from OUTSIDE this workflow (job
`auto-merge` reports its own SUCCESS on every Dependabot PR it runs against,
so counting only checks from this workflow would let the gate satisfy
itself), and pins the merge to the head commit it just judged with
`--match-head-commit` so a mid-flight push -- Dependabot rebases its other
open PRs each time a sibling merges -- can't get merged un-reviewed.

The structural test below locks `auto-merge`'s step list so the deleted
"Attempt auto-merge" step (and its `|| true`) cannot come back unnoticed. The
behavioural tests execute the ACTUAL `sweep` job's "Sweep open Dependabot
PRs" `run:` script -- extracted by parsing the workflow, never copied by hand
-- against stubbed `gh`/`git`, so a future edit to that bash is exercised for
real rather than re-described in Python.

Parsed with PyYAML, never regex- or line-scanned, for the same reason
tests/test_ci_workflow.py gives: a scan reads clean on YAML it cannot see --
inside a quoted block, or behind an anchor.
"""

import json
import os
import subprocess
from pathlib import Path
from shutil import which

import pytest

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard, not a code path
    raise ImportError(
        "PyYAML is required to parse .github/workflows/dependabot-auto-merge.yml "
        "structurally; a regex or line scan reads clean on YAML it cannot see (a "
        "quoted block, an anchor). ci.yml's 'Install dependencies' step already "
        "installs it for tests/test_ci_workflow.py -- restore that package rather "
        "than skipping this module. Never pytest.importorskip here: a silent skip "
        "is exactly the failure this file exists to close."
    ) from exc

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "dependabot-auto-merge.yml"

EXPECTED_AUTO_MERGE_STEP_NAMES = [
    "Checkout",
    "Fetch base ref",
    "Get Dependabot metadata",
    "Verify only manifest paths changed",
    "Disable auto-merge (path check failed)",
]

SWEEP_STEP_NAME = "Sweep open Dependabot PRs"


def _load_workflow():
    """Parse dependabot-auto-merge.yml into a non-empty mapping, failing loudly if not."""
    assert WORKFLOW_PATH.is_file(), f"{WORKFLOW_PATH} is missing."
    text = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert text.strip(), f"{WORKFLOW_PATH} is empty; there is nothing here to have checked."
    doc = yaml.safe_load(text)
    assert isinstance(doc, dict) and doc, (
        f"{WORKFLOW_PATH} did not parse to a non-empty mapping (got {type(doc).__name__})."
    )
    return doc


def _job(doc, name):
    jobs = doc.get("jobs")
    assert isinstance(jobs, dict) and jobs, f"{WORKFLOW_PATH} declares no jobs."
    assert name in jobs, f"{WORKFLOW_PATH} has no `{name}` job (jobs: {sorted(jobs)})."
    return jobs[name]


def _sweep_script():
    """Return the exact `run:` script of the sweep job's "Sweep open Dependabot PRs" step."""
    sweep = _job(_load_workflow(), "sweep")
    steps = sweep.get("steps")
    assert isinstance(steps, list) and steps, "`sweep` job declares no steps."
    for step in steps:
        if isinstance(step, dict) and step.get("name") == SWEEP_STEP_NAME:
            run = step.get("run")
            assert isinstance(run, str) and run.strip(), (
                f"`{SWEEP_STEP_NAME}` step has no `run:` script."
            )
            return run
    raise AssertionError(
        f"`sweep` job has no step named {SWEEP_STEP_NAME!r} (steps: "
        f"{[s.get('name') for s in steps if isinstance(s, dict)]})."
    )


def test_workflow_parses_and_declares_both_jobs():
    """Vacuity floor: the file exists, parses, and still declares both jobs."""
    doc = _load_workflow()
    _job(doc, "auto-merge")
    _job(doc, "sweep")


def test_auto_merge_job_never_attempts_a_merge():
    """`auto-merge`'s step list must not regain a merge attempt.

    cms-platform#437 (https://github.com/Adam-S-Daniel/cms-platform/issues/437):
    `gh pr merge --auto` merges a Dependabot PR on the spot the moment this
    repo has no required status check for it to wait on -- it does not
    no-op, and the trailing `|| true` the old "Attempt auto-merge" step
    carried hid every merge it made before CI had reported. That step must
    stay gone; only job `sweep`'s CI-gated merge below is allowed to call
    `gh pr merge` for a Dependabot PR.
    """
    auto_merge = _job(_load_workflow(), "auto-merge")
    steps = auto_merge.get("steps")
    assert isinstance(steps, list) and steps, "`auto-merge` job declares no steps."
    names = [s.get("name") for s in steps if isinstance(s, dict)]
    assert names == EXPECTED_AUTO_MERGE_STEP_NAMES, (
        f"`auto-merge` job's steps are {names}, not the expected "
        f"{EXPECTED_AUTO_MERGE_STEP_NAMES}. cms-platform#437 "
        "(https://github.com/Adam-S-Daniel/cms-platform/issues/437) found that "
        "`gh pr merge --auto` merges a Dependabot PR on the spot when nothing is "
        "required -- it does not wait for CI, and the trailing `|| true` on the "
        "old 'Attempt auto-merge' step hid every merge it made before CI had "
        "even reported. If a step was added back here, confirm it never calls "
        "`gh pr merge` before keeping it."
    )


# --------------------------------------------------------------------------
# Behavioural: execute the real sweep script against stubbed gh/git.
# --------------------------------------------------------------------------

GH_STUB = """#!/usr/bin/env bash
set -u
echo "$*" >> "$FIXTURES/calls.log"

cmd="${1:-}"
sub="${2:-}"

case "$cmd" in
  pr)
    case "$sub" in
      list)
        cat "$FIXTURES/pr-numbers.txt"
        exit 0
        ;;
      view)
        num="$3"
        counter_file="$FIXTURES/view-count-${num}.txt"
        count=0
        if [ -f "$counter_file" ]; then
          count=$(cat "$counter_file")
        fi
        count=$((count + 1))
        echo "$count" > "$counter_file"
        after="$FIXTURES/pr-${num}.after.json"
        base="$FIXTURES/pr-${num}.json"
        if [ "$count" -gt 1 ] && [ -f "$after" ]; then
          cat "$after"
        else
          cat "$base"
        fi
        exit 0
        ;;
      merge)
        last="${!#}"
        fails=" ${MERGE_FAILS:-} "
        if [[ "$fails" == *" ${last} "* ]]; then
          echo "gh: pull request #${last} is not mergeable at this time" >&2
          exit 1
        fi
        exit 0
        ;;
      update-branch)
        exit 0
        ;;
      *)
        exit 90
        ;;
    esac
    ;;
  api)
    echo '{"message":"Not Found"}'
    exit 1
    ;;
  *)
    exit 90
    ;;
esac
"""

GIT_STUB = """#!/usr/bin/env bash
set -u
cmd="${1:-}"
case "$cmd" in
  fetch)
    exit 0
    ;;
  diff)
    echo ".github/workflows/ci.yml"
    exit 0
    ;;
  *)
    exit 90
    ;;
esac
"""


def _require(binary):
    if which(binary) is None:
        pytest.fail(
            f"{binary!r} is not on PATH -- this suite executes the sweep step's "
            f"real bash+jq script against stubs, so it cannot fail loudly without "
            f"a real {binary}. Install it rather than skipping this module."
        )


def _write_stub_bin(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, content in (("gh", GH_STUB), ("git", GIT_STUB)):
        stub = bin_dir / name
        stub.write_text(content, encoding="utf-8")
        stub.chmod(0o755)
    return bin_dir


def _prepare_fixtures_dir(tmp_path):
    fixtures_dir = tmp_path / "fixtures"
    fixtures_dir.mkdir()
    return fixtures_dir


def _write_pr_fixture(fixtures_dir, number, fixture, after=None):
    (fixtures_dir / f"pr-{number}.json").write_text(json.dumps(fixture), encoding="utf-8")
    if after is not None:
        (fixtures_dir / f"pr-{number}.after.json").write_text(json.dumps(after), encoding="utf-8")


def _run_sweep(tmp_path, fixtures_dir, pr_numbers, self_workflow="Dependabot auto-merge", merge_fails=""):
    _require("bash")
    _require("jq")
    script = _sweep_script()

    (fixtures_dir / "pr-numbers.txt").write_text(
        "".join(f"{n}\n" for n in pr_numbers), encoding="utf-8"
    )
    bin_dir = _write_stub_bin(tmp_path)

    env = dict(os.environ)
    env.pop("GH_TOKEN", None)
    env.pop("GITHUB_TOKEN", None)
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    env["FIXTURES"] = str(fixtures_dir)
    env["GITHUB_REPOSITORY"] = "Adam-S-Daniel/GHA-bench"
    env["SELF_WORKFLOW"] = self_workflow
    env["MERGE_FAILS"] = merge_fails

    result = subprocess.run(
        ["bash", "-c", script],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    calls_log = fixtures_dir / "calls.log"
    calls = calls_log.read_text(encoding="utf-8") if calls_log.exists() else ""
    return result, calls


def _merge_calls(calls):
    return [line for line in calls.splitlines() if line.startswith("pr merge")]


def _update_branch_calls(calls):
    return [line for line in calls.splitlines() if line.startswith("pr update-branch")]


def test_sweep_case_a_merges_pinned_to_head_when_an_outside_check_is_green(tmp_path):
    """(a) CI `test` SUCCESS + own `auto-merge` SUCCESS -> one pinned merge."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    head = "a" * 40
    _write_pr_fixture(
        fixtures_dir,
        201,
        {
            "number": 201,
            "baseRefName": "main",
            "headRefOid": head,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
                {"workflowName": "Dependabot auto-merge", "name": "auto-merge", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [201])

    assert result.returncode == 0, result.stdout + result.stderr
    merge_calls = _merge_calls(calls)
    assert len(merge_calls) == 1, f"expected exactly one merge attempt, got: {calls!r}"
    assert f"--match-head-commit {head}" in merge_calls[0]
    assert merge_calls[0].split()[-1] == "201"
    assert "merged=1 updated=0 skipped=0 blocked=0 failed=0" in result.stdout


def test_sweep_case_b_skips_when_every_check_is_from_this_workflow(tmp_path):
    """(b) only own-workflow checks -> no merge, skipped, named reason."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    head = "b" * 40
    _write_pr_fixture(
        fixtures_dir,
        202,
        {
            "number": 202,
            "baseRefName": "main",
            "headRefOid": head,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "Dependabot auto-merge", "name": "auto-merge", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [202])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "every check on its head comes from this workflow" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_case_c_null_conclusion_blocks_merge(tmp_path):
    """(c) a check with conclusion None (still running) -> no merge."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    head = "c" * 40
    _write_pr_fixture(
        fixtures_dir,
        203,
        {
            "number": 203,
            "baseRefName": "main",
            "headRefOid": head,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": None},
                {"workflowName": "Dependabot auto-merge", "name": "auto-merge", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [203])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_case_d_skips_when_head_moved_after_a_refused_merge(tmp_path):
    """(d) merge refused + after.json shows a different head -> skip, no update-branch."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    old_head = "d" * 40
    new_head = "e" * 40
    _write_pr_fixture(
        fixtures_dir,
        204,
        {
            "number": 204,
            "baseRefName": "main",
            "headRefOid": old_head,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BEHIND",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
        after={"headRefOid": new_head},
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [204], merge_fails="204")

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _update_branch_calls(calls), f"expected no update-branch call, got: {calls!r}"
    assert "its head moved" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_case_e_empty_self_workflow_refuses_to_run(tmp_path):
    """(e) SELF_WORKFLOW="" -> non-zero exit, no gh calls at all."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)

    result, calls = _run_sweep(tmp_path, fixtures_dir, [], self_workflow="")

    assert result.returncode != 0, result.stdout + result.stderr
    assert calls == "", f"expected no gh calls, got: {calls!r}"
    assert not _merge_calls(calls)


def test_sweep_case_f_invalid_head_sha_blocks_merge(tmp_path):
    """(f) headRefOid "abc" (not 40-hex) -> no merge."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    _write_pr_fixture(
        fixtures_dir,
        206,
        {
            "number": 206,
            "baseRefName": "main",
            "headRefOid": "abc",
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [206])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "is not a 40-hex sha" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_case_g_refreshes_a_behind_pr_with_unchanged_head(tmp_path):
    """(g) merge refused, head unchanged, BEHIND -> update-branch, updated=1."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    head = "7" * 40
    _write_pr_fixture(
        fixtures_dir,
        207,
        {
            "number": 207,
            "baseRefName": "main",
            "headRefOid": head,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BEHIND",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
        after={"headRefOid": head},
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [207], merge_fails="207")

    assert result.returncode == 0, result.stdout + result.stderr
    assert _update_branch_calls(calls), f"expected an update-branch call, got: {calls!r}"
    assert "merged=0 updated=1 skipped=0 blocked=0 failed=0" in result.stdout
