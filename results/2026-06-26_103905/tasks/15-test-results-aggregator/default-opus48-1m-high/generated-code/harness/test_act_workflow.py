"""Workflow validation harness.

This suite validates the GitHub Actions workflow two ways:

1. **Structure / static checks** (fast): actionlint passes, the YAML has the
   expected triggers/jobs/steps, and it references scripts that actually exist.
2. **Execution through act** (slow): every test case is run through the real
   workflow with ``act push --rm``. For each case we assert act exited 0,
   every job shows "Job succeeded", and the aggregator emitted the EXACT
   known-good totals/flaky lines for that fixture input.

The harness deliberately lives outside ``tests/`` so the workflow's own
``pytest tests/`` step never tries to launch act from inside the act
container (which would be docker-in-docker recursion).

Run with:  python3 -m pytest harness/ -v -s
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

import pytest
import yaml

import cases  # harness/cases.py (same directory, on sys.path under pytest)

# Repo root = parent of this harness/ directory.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "test-results-aggregator.yml")
ACT_RESULT = os.path.join(ROOT, "act-result.txt")


# ---------------------------------------------------------------------------
# Static structure checks (no act required).
# ---------------------------------------------------------------------------

def test_actionlint_passes():
    """actionlint must validate the workflow cleanly (exit 0)."""
    proc = subprocess.run(
        ["actionlint", WORKFLOW],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


def _load_workflow():
    with open(WORKFLOW, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_has_expected_triggers():
    wf = _load_workflow()
    # PyYAML parses the bare YAML key `on:` as the boolean True.
    triggers = wf.get("on", wf.get(True))
    assert set(triggers) >= {"push", "pull_request", "schedule", "workflow_dispatch"}
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"


def test_workflow_jobs_and_dependencies():
    wf = _load_workflow()
    jobs = wf["jobs"]
    assert {"unit-tests", "aggregate"} <= set(jobs)
    # aggregate must wait for the unit tests.
    assert jobs["aggregate"]["needs"] == "unit-tests"
    # Least-privilege permissions declared.
    assert wf["permissions"]["contents"] == "read"
    # Env var that points the aggregator at the results directory.
    assert "TEST_RESULTS_DIR" in wf["env"]


def test_workflow_uses_checkout_v4():
    wf = _load_workflow()
    for job in wf["jobs"].values():
        uses = [s.get("uses", "") for s in job["steps"]]
        assert "actions/checkout@v4" in uses


def test_workflow_references_existing_scripts():
    """The paths the workflow runs must exist in the repo."""
    assert os.path.isfile(os.path.join(ROOT, "aggregator.py"))
    assert os.path.isdir(os.path.join(ROOT, "tests"))
    text = open(WORKFLOW, encoding="utf-8").read()
    assert "python3 aggregator.py" in text
    assert "pytest tests/" in text


# ---------------------------------------------------------------------------
# Execution through act.
# ---------------------------------------------------------------------------

def _setup_repo(tmp_path, case):
    """Build an isolated git repo: project files + this case's fixtures."""
    repo = tmp_path / "repo"
    repo.mkdir()

    # Copy the project files the workflow needs.
    for item in ["aggregator.py", "conftest.py", "tests", ".github", ".actrc"]:
        src = os.path.join(ROOT, item)
        dst = repo / item
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    # Materialize this case's fixtures into test-results/.
    results = repo / "test-results"
    results.mkdir()
    for filename, content in case.files.items():
        (results / filename).write_text(content)

    # act needs a git repo with at least one commit.
    env = {**os.environ, "GIT_AUTHOR_NAME": "h", "GIT_AUTHOR_EMAIL": "h@h",
           "GIT_COMMITTER_NAME": "h", "GIT_COMMITTER_EMAIL": "h@h"}
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "fixture"], cwd=repo,
                   check=True, env=env)
    return repo


def _run_act(repo):
    """Run the workflow via act push and return (returncode, combined_output)."""
    # --pull=false: the runner image (act-ubuntu-pwsh) is built locally and has
    # no registry, so act's default force-pull would fail with an auth error.
    proc = subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo, capture_output=True, text=True, timeout=600,
    )
    return proc.returncode, proc.stdout + "\n" + proc.stderr


def _append_result(case_name, rc, output):
    """Append this case's act output to act-result.txt, clearly delimited."""
    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write("\n" + "=" * 78 + "\n")
        fh.write(f"TEST CASE: {case_name}  (act exit code: {rc})\n")
        fh.write("=" * 78 + "\n")
        fh.write(output)
        fh.write("\n")


# Truncate act-result.txt exactly once, on the first act case that actually
# runs. Done here (not in a session fixture) so that running only the static
# structure tests never wipes the artifact from a prior act run.
_truncated: list[int] = []


@pytest.mark.parametrize("case", cases.ALL_CASES, ids=lambda c: c.name)
def test_workflow_runs_through_act(tmp_path, case):
    if not _truncated:
        open(ACT_RESULT, "w", encoding="utf-8").close()
        _truncated.append(1)

    repo = _setup_repo(tmp_path, case)
    rc, output = _run_act(repo)
    _append_result(case.name, rc, output)

    # 1) act must exit successfully.
    assert rc == 0, f"act exited {rc} for case {case.name}:\n{output[-3000:]}"

    # 2) Every job must report success, and none may fail.
    assert "Job failed" not in output, f"a job failed in {case.name}:\n{output[-3000:]}"
    # Two jobs (unit-tests + aggregate) -> at least two success markers.
    assert output.count("Job succeeded") >= 2, (
        f"expected 2 'Job succeeded' in {case.name}, got "
        f"{output.count('Job succeeded')}:\n{output[-3000:]}"
    )

    # 3) Exact aggregator output for this fixture input.
    for line in case.expected_lines:
        assert line in output, (
            f"missing expected line for {case.name}: {line!r}\n{output[-3000:]}"
        )


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v", "-s"]))
