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
printf '%s\\n' "$*" >> "$FIXTURES/git-calls.log"
cmd="${1:-}"
case "$cmd" in
  fetch)
    exit 0
    ;;
  diff)
    if [ -f "$FIXTURES/diff-fails" ]; then
      echo "fatal: bad revision" >&2
      exit 128
    fi
    if [ -f "$FIXTURES/diff.txt" ]; then
      cat "$FIXTURES/diff.txt"
    else
      echo ".github/workflows/ci.yml"
    fi
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


def _git_diff_calls(fixtures_dir):
    """argv (split on whitespace) of every `git diff` the stubbed git received."""
    log = fixtures_dir / "git-calls.log"
    lines = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    return [line.split() for line in lines if line.split()[:1] == ["diff"]]


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


# --------------------------------------------------------------------------
# Benchmark output under results/ or workspaces/ is never auto-merged.
#
# AGENTS.md ("Never fix agent-generated code") forbids patching anything in
# workspaces/ or results/*/generated-code/, and .github/dependabot.yml calls
# results/** output data, not source. Dependabot SECURITY updates opened PRs
# against those manifests (GHA-bench#92 bumped a package-lock.json and #93 a
# package.json inside results/2026-05-06_173435/), and the manifest allowlist
# alone accepted them.
# Both jobs now share one inlined `classify_path` function between BEGIN/END
# marker comments; these tests lock the two copies together, execute them, and
# check that each job runs `git diff --no-renames` and fails closed when the
# diff fails or lists nothing.
# --------------------------------------------------------------------------

AUTO_MERGE_PATHS_STEP_NAME = "Verify only manifest paths changed"
CLASSIFIER_BEGIN = "# BEGIN dependabot-path-classifier"
CLASSIFIER_END = "# END dependabot-path-classifier"

# path -> class the classifier must print for it.
CLASSIFIER_CASES = {
    "package.json": "manifest",
    "results/2026-05-06_173435/tasks/x/generated-code/package-lock.json": "benchmark-output",
    "workspaces/a/package.json": "benchmark-output",
    "docs/results-notes/package.json": "manifest",
    "src/workspaces-notes/requirements.txt": "manifest",
    ".github/workflows/ci.yml": "manifest",
    "results/README.md": "benchmark-output",
    "README.md": "other",
}


def _step_run(job_name, step_name):
    job = _job(_load_workflow(), job_name)
    steps = job.get("steps")
    assert isinstance(steps, list) and steps, f"`{job_name}` job declares no steps."
    for step in steps:
        if isinstance(step, dict) and step.get("name") == step_name:
            run = step.get("run")
            assert isinstance(run, str) and run.strip(), (
                f"`{job_name}` step {step_name!r} has no `run:` script."
            )
            return run
    raise AssertionError(f"`{job_name}` job has no step named {step_name!r}.")


def _classifier_block(job_name, step_name):
    """Return the dedented lines between the BEGIN/END classifier markers.

    The workflow is parsed with PyYAML to reach the `run:` script; within that
    script the markers are lexical tokens, matched as whole stripped lines.
    """
    lines = _step_run(job_name, step_name).splitlines()
    stripped = [line.strip() for line in lines]
    assert stripped.count(CLASSIFIER_BEGIN) == 1 and stripped.count(CLASSIFIER_END) == 1, (
        f"`{job_name}` / {step_name!r} must carry exactly one {CLASSIFIER_BEGIN!r} and "
        f"one {CLASSIFIER_END!r} line."
    )
    begin = stripped.index(CLASSIFIER_BEGIN)
    end = stripped.index(CLASSIFIER_END)
    assert begin < end, f"`{job_name}`: classifier END marker precedes BEGIN."
    return stripped[begin : end + 1]


def _both_classifier_blocks():
    return {
        "auto-merge": _classifier_block("auto-merge", AUTO_MERGE_PATHS_STEP_NAME),
        "sweep": _classifier_block("sweep", SWEEP_STEP_NAME),
    }


def test_path_classifier_is_identical_in_both_jobs():
    blocks = _both_classifier_blocks()
    assert blocks["auto-merge"] == blocks["sweep"], (
        "The inlined classify_path blocks in jobs `auto-merge` and `sweep` have "
        "drifted apart; the workflow header requires them to stay identical."
    )


@pytest.mark.parametrize("job_name", ["auto-merge", "sweep"])
def test_benchmark_output_arm_precedes_manifest_arms(job_name):
    """`case` takes the first matching arm, so results/ + workspaces/ must come first."""
    block = _both_classifier_blocks()[job_name]
    bench = [i for i, line in enumerate(block) if line.startswith("results/*|workspaces/*)")]
    manifest = [i for i, line in enumerate(block) if "package.json" in line and line.endswith(";;")]
    assert len(bench) == 1, f"`{job_name}`: no single `results/*|workspaces/*)` arm in {block!r}."
    assert "benchmark-output" in block[bench[0]], f"`{job_name}`: {block[bench[0]]!r}"
    assert manifest, f"`{job_name}`: no package.json manifest arm in {block!r}."
    assert bench[0] < min(manifest), (
        f"`{job_name}`: the results/ + workspaces/ exclusion must precede the "
        "manifest allowlist, or a manifest under results/ matches the allowlist first."
    )


@pytest.mark.parametrize("job_name", ["auto-merge", "sweep"])
def test_classifier_executes_on_sample_paths(job_name, tmp_path):
    _require("bash")
    block = "\n".join(_both_classifier_blocks()[job_name])
    paths_file = tmp_path / "paths.txt"
    paths_file.write_text("".join(f"{p}\n" for p in CLASSIFIER_CASES), encoding="utf-8")
    script = (
        "set -euo pipefail\n"
        f"{block}\n"
        'while IFS= read -r p; do printf \'%s\\t%s\\n\' "$p" "$(classify_path "$p")"; done < "$1"\n'
    )
    result = subprocess.run(
        ["bash", "-c", script, "classify", paths_file.name],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    got = dict(line.split("\t", 1) for line in result.stdout.splitlines())
    assert got == CLASSIFIER_CASES


def _auto_merge_paths_step():
    job = _job(_load_workflow(), "auto-merge")
    for step in job.get("steps") or []:
        if isinstance(step, dict) and step.get("name") == AUTO_MERGE_PATHS_STEP_NAME:
            return step
    raise AssertionError(f"`auto-merge` job has no step named {AUTO_MERGE_PATHS_STEP_NAME!r}.")


def _run_auto_merge_paths_step(tmp_path, changed_paths, diff_fails=False):
    """Execute the real `auto-merge` path-check step against a stubbed git.

    Returns (result, GITHUB_OUTPUT contents, argv of each `git diff` call).
    """
    _require("bash")
    step = _auto_merge_paths_step()
    script = step.get("run")
    assert isinstance(script, str) and script.strip()
    assert "${{" not in script, "the `auto-merge` path-check step interpolates an expression into `run:`."
    # Event data arrives through the step's `env:`; supply test values for it.
    step_env = step.get("env") or {}
    assert set(step_env) == {"BASE_REF", "HEAD_SHA"}, f"unexpected step env: {sorted(step_env)}"

    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    (fixtures_dir / "diff.txt").write_text("".join(f"{p}\n" for p in changed_paths), encoding="utf-8")
    if diff_fails:
        (fixtures_dir / "diff-fails").write_text("", encoding="utf-8")
    output_file = tmp_path / "github_output"
    output_file.write_text("", encoding="utf-8")
    bin_dir = _write_stub_bin(tmp_path)

    env = dict(os.environ)
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    env["FIXTURES"] = str(fixtures_dir)
    env["GITHUB_OUTPUT"] = str(output_file)
    env["BASE_REF"] = "main"
    env["HEAD_SHA"] = "f" * 40
    result = subprocess.run(
        ["bash", "-c", script], cwd=tmp_path, env=env, capture_output=True, text=True, timeout=30
    )
    return result, output_file.read_text(encoding="utf-8"), _git_diff_calls(fixtures_dir)


def test_auto_merge_marks_root_manifest_safe(tmp_path):
    result, outputs, _ = _run_auto_merge_paths_step(tmp_path, ["package.json"])
    assert result.returncode == 0, result.stdout + result.stderr
    assert outputs.splitlines() == ["safe=true"]


def test_auto_merge_diff_disables_rename_detection(tmp_path):
    """A rename out of results/ must list its source path, not just its destination."""
    result, _, diff_calls = _run_auto_merge_paths_step(tmp_path, ["package.json"])
    assert result.returncode == 0, result.stdout + result.stderr
    assert len(diff_calls) == 1, f"expected one git diff call, got {diff_calls!r}"
    assert "--no-renames" in diff_calls[0], diff_calls[0]


def test_auto_merge_failed_diff_is_not_safe(tmp_path):
    result, outputs, _ = _run_auto_merge_paths_step(tmp_path, ["package.json"], diff_fails=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert outputs.splitlines() == ["safe=false"]
    assert "failed, so the changed paths are unknown" in result.stdout


def test_auto_merge_empty_diff_is_not_safe(tmp_path):
    result, outputs, _ = _run_auto_merge_paths_step(tmp_path, [])
    assert result.returncode == 0, result.stdout + result.stderr
    assert outputs.splitlines() == ["safe=false"]
    assert "lists no changed files" in result.stdout


@pytest.mark.parametrize(
    "path",
    [
        "results/2026-05-06_173435/tasks/x/generated-code/package-lock.json",
        "workspaces/a/package.json",
    ],
)
def test_auto_merge_marks_benchmark_output_unsafe(tmp_path, path):
    result, outputs, _ = _run_auto_merge_paths_step(tmp_path, ["package.json", path])
    assert result.returncode == 0, result.stdout + result.stderr
    assert outputs.splitlines() == ["safe=false"]
    assert "benchmark output under results/ or workspaces/" in result.stdout


def test_sweep_skips_a_pr_touching_benchmark_output(tmp_path):
    """Green checks and manifest-only paths, but under results/ -> no merge, reason named."""
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    (fixtures_dir / "diff.txt").write_text(
        "results/2026-05-06_173435/tasks/x/generated-code/package-lock.json\n", encoding="utf-8"
    )
    _write_pr_fixture(
        fixtures_dir,
        208,
        {
            "number": 208,
            "baseRefName": "main",
            "headRefOid": "8" * 40,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [208])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "skip #208 — diff touches benchmark output under results/ or workspaces/" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_still_merges_a_manifest_whose_path_merely_mentions_results(tmp_path):
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    (fixtures_dir / "diff.txt").write_text("docs/results-notes/package.json\n", encoding="utf-8")
    _write_pr_fixture(
        fixtures_dir,
        209,
        {
            "number": 209,
            "baseRefName": "main",
            "headRefOid": "9" * 40,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
    )

    result, calls = _run_sweep(tmp_path, fixtures_dir, [209])

    assert result.returncode == 0, result.stdout + result.stderr
    assert len(_merge_calls(calls)) == 1, f"expected one merge attempt, got: {calls!r}"
    assert "merged=1 updated=0 skipped=0 blocked=0 failed=0" in result.stdout


def _clean_sweep_fixture(fixtures_dir, number, head_char):
    _write_pr_fixture(
        fixtures_dir,
        number,
        {
            "number": number,
            "baseRefName": "main",
            "headRefOid": head_char * 40,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
                {"workflowName": "CI", "name": "test", "conclusion": "SUCCESS"},
            ],
        },
    )


def test_sweep_diff_disables_rename_detection(tmp_path):
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    _clean_sweep_fixture(fixtures_dir, 210, "a")

    result, _calls = _run_sweep(tmp_path, fixtures_dir, [210])

    assert result.returncode == 0, result.stdout + result.stderr
    diff_calls = _git_diff_calls(fixtures_dir)
    assert len(diff_calls) == 1, f"expected one git diff call, got {diff_calls!r}"
    assert "--no-renames" in diff_calls[0], diff_calls[0]


def test_sweep_skips_when_git_diff_fails(tmp_path):
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    (fixtures_dir / "diff-fails").write_text("", encoding="utf-8")
    _clean_sweep_fixture(fixtures_dir, 211, "b")

    result, calls = _run_sweep(tmp_path, fixtures_dir, [211])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "skip #211 — git diff against main failed" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_sweep_skips_when_diff_lists_no_files(tmp_path):
    fixtures_dir = _prepare_fixtures_dir(tmp_path)
    (fixtures_dir / "diff.txt").write_text("", encoding="utf-8")
    _clean_sweep_fixture(fixtures_dir, 212, "c")

    result, calls = _run_sweep(tmp_path, fixtures_dir, [212])

    assert result.returncode == 0, result.stdout + result.stderr
    assert not _merge_calls(calls), f"expected no merge attempt, got: {calls!r}"
    assert "skip #212 — diff against main lists no changed files" in result.stdout
    assert "merged=0 updated=0 skipped=1 blocked=0 failed=0" in result.stdout


def test_no_run_block_interpolates_event_or_input_data():
    """Event and input data reach a `run:` script only through `env:`.

    An expression rendered into the script text is echoed to the public log
    and parsed as shell; read through `env:` and quoted, it is only data.
    """
    doc = _load_workflow()
    offenders = []
    for job_name, job in (doc.get("jobs") or {}).items():
        for step in (job or {}).get("steps") or []:
            run = step.get("run") if isinstance(step, dict) else None
            if isinstance(run, str) and ("${{ github.event." in run or "${{ inputs." in run):
                offenders.append(f"{job_name} / {step.get('name')}")
    assert not offenders, f"`run:` blocks interpolating event/input data: {offenders}"
