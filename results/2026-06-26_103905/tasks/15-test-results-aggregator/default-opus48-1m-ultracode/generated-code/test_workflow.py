"""Workflow-level tests for the Test Results Aggregator.

Two layers:

1. Static structure tests -- parse the workflow YAML, assert its triggers /
   jobs / steps, confirm it references files that actually exist, and confirm
   `actionlint` passes.

2. End-to-end pipeline tests -- per the benchmark contract, the workflow is
   exercised through `act` (nektos/act) in Docker. For *each* test case we set
   up a throwaway git repo containing the project files plus that case's
   fixture data, run `act push --rm`, append the full output to
   `act-result.txt`, and assert on the EXACT aggregated values the workflow
   should have produced for that input.
"""
import os
import shutil
import subprocess

import pytest
import yaml

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKFLOW_PATH = os.path.join(
    PROJECT_DIR, ".github", "workflows", "test-results-aggregator.yml"
)
ACT_RESULT_FILE = os.path.join(PROJECT_DIR, "act-result.txt")


# ===========================================================================
# Layer 1: static workflow structure
# ===========================================================================
@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH), "workflow YAML is missing"


def test_workflow_has_expected_triggers(workflow):
    # PyYAML parses the bare `on:` key as the boolean True, so accept either.
    triggers = workflow.get("on", workflow.get(True))
    assert set(triggers) >= {"push", "pull_request", "workflow_dispatch", "schedule"}
    # schedule must carry a cron entry.
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"


def test_workflow_has_two_jobs_with_dependency(workflow):
    jobs = workflow["jobs"]
    assert set(jobs) == {"validate", "aggregate"}
    # the aggregate (fan-in) job must depend on the validate (fan-out) job.
    assert jobs["aggregate"]["needs"] == "validate"


def test_workflow_permissions_are_read_only(workflow):
    assert workflow["permissions"] == {"contents": "read"}


def test_validate_job_is_a_matrix_over_the_three_fixtures(workflow):
    matrix = workflow["jobs"]["validate"]["strategy"]["matrix"]
    assert set(matrix["fixture"]) == {
        "results-ubuntu.xml",
        "results-windows.json",
        "results-macos.xml",
    }


def test_jobs_checkout_with_pinned_action(workflow):
    for job in workflow["jobs"].values():
        steps = job["steps"]
        assert steps[0]["uses"] == "actions/checkout@v4"


def test_workflow_invokes_the_aggregator_script(workflow):
    # collect every `run:` line across both jobs.
    runs = "\n".join(
        step.get("run", "")
        for job in workflow["jobs"].values()
        for step in job["steps"]
    )
    assert "aggregator.py" in runs
    assert "--validate" in runs  # used by the matrix legs
    assert "--format json" in runs  # machine-readable output for verification
    assert "GITHUB_STEP_SUMMARY" in runs  # publishes the markdown summary


def test_workflow_references_existing_files():
    # the script the workflow runs must exist...
    assert os.path.isfile(os.path.join(PROJECT_DIR, "aggregator.py"))
    # ...and every fixture named in the matrix must exist on disk.
    for fixture in ("results-ubuntu.xml", "results-windows.json", "results-macos.xml"):
        assert os.path.isfile(os.path.join(PROJECT_DIR, "fixtures", fixture))


def test_actionlint_passes():
    """actionlint must validate the workflow cleanly (exit code 0)."""
    proc = subprocess.run(
        ["actionlint", WORKFLOW_PATH],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


# ===========================================================================
# Layer 2: end-to-end execution through `act`
# ===========================================================================
# Green fixture set used by the "all-green" case. Same filenames as the matrix
# expects, but every test passes => 6 passed, 0 failed, 0 flaky.
GREEN_UBUNTU_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="s" tests="2" failures="0" errors="0" skipped="0" time="1.0">
  <testcase classname="c" name="test_add" time="0.5"/>
  <testcase classname="c" name="test_subtract" time="0.5"/>
</testsuite>
"""
GREEN_MACOS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="s" tests="2" failures="0" errors="0" skipped="0" time="1.0">
  <testcase classname="c" name="test_add" time="0.5"/>
  <testcase classname="c" name="test_subtract" time="0.5"/>
</testsuite>
"""
GREEN_WINDOWS_JSON = """{
  "name": "s",
  "tests": [
    {"classname": "c", "name": "test_add", "status": "passed", "time": 0.5},
    {"classname": "c", "name": "test_subtract", "status": "passed", "time": 0.5}
  ]
}
"""

# Each case: an id, optional fixture overrides (filename -> contents), the
# substrings that MUST appear in the act output, and substrings that must NOT.
ACT_CASES = [
    pytest.param(
        {
            "id": "flaky-matrix",
            "fixtures": None,  # use the repo's own (flaky) fixtures
            "expect": [
                '"passed": 8',
                '"failed": 2',
                '"skipped": 2',
                '"total": 12',
                '"duration": 9.2',
                "tests.test_net::test_connect",  # the one flaky test
                "Flaky Tests (1)",
                "FAILED",  # overall status (markdown)
            ],
            "forbid": ["No flaky tests detected"],
        },
        id="flaky-matrix",
    ),
    pytest.param(
        {
            "id": "all-green",
            "fixtures": {
                "results-ubuntu.xml": GREEN_UBUNTU_XML,
                "results-macos.xml": GREEN_MACOS_XML,
                "results-windows.json": GREEN_WINDOWS_JSON,
            },
            "expect": [
                '"passed": 6',
                '"failed": 0',
                '"total": 6',
                '"duration": 3.0',
                "No flaky tests detected",
                "Flaky Tests (0)",
                "PASSED",  # overall status (markdown)
            ],
            "forbid": ["tests.test_net::test_connect"],
        },
        id="all-green",
    ),
]


def _have_tool(name):
    return shutil.which(name) is not None


requires_act = pytest.mark.skipif(
    not (_have_tool("act") and _have_tool("docker")),
    reason="act and/or docker not available",
)


def _stage_repo(tmp_path, fixtures_override):
    """Materialize a self-contained git repo for one act run."""
    repo = tmp_path / "repo"
    repo.mkdir()
    # Project files the workflow needs.
    shutil.copy(os.path.join(PROJECT_DIR, "aggregator.py"), repo / "aggregator.py")
    shutil.copytree(
        os.path.join(PROJECT_DIR, ".github"), repo / ".github"
    )
    # Copy the act platform mapping so `act` picks the right runner image.
    actrc = os.path.join(PROJECT_DIR, ".actrc")
    if os.path.isfile(actrc):
        shutil.copy(actrc, repo / ".actrc")

    # Fixtures: either the repo's own, or this case's overrides.
    fixtures_dir = repo / "fixtures"
    fixtures_dir.mkdir()
    if fixtures_override is None:
        for fn in ("results-ubuntu.xml", "results-windows.json", "results-macos.xml"):
            shutil.copy(os.path.join(PROJECT_DIR, "fixtures", fn), fixtures_dir / fn)
    else:
        for fn, content in fixtures_override.items():
            (fixtures_dir / fn).write_text(content)

    # A committed git repo is required for `act push` / checkout.
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True, env=env)
    subprocess.run(
        ["git", "commit", "-q", "-m", "fixture"], cwd=repo, check=True, env=env
    )
    return repo


# Tracks whether THIS pytest session has written to act-result.txt yet, so the
# first act case truncates (fresh run) and later cases append. Crucially, the
# file is only ever truncated when an act case actually runs -- a partial test
# session that skips the act tests leaves the existing artifact untouched.
_act_session_started: list[bool] = []


def _record(case_id, exit_code, output):
    """Append one case's act output to the required act-result.txt artifact."""
    if not _act_session_started:
        _act_session_started.append(True)
        with open(ACT_RESULT_FILE, "w", encoding="utf-8") as fh:
            fh.write("act-result.txt -- output of `act push --rm` per test case\n")
    with open(ACT_RESULT_FILE, "a", encoding="utf-8") as fh:
        fh.write("\n" + "=" * 78 + "\n")
        fh.write(f"ACT TEST CASE: {case_id}  (exit code: {exit_code})\n")
        fh.write("=" * 78 + "\n")
        fh.write(output)
        fh.write("\n")


@requires_act
@pytest.mark.parametrize("case", ACT_CASES)
def test_workflow_runs_through_act(case, tmp_path):
    repo = _stage_repo(tmp_path, case["fixtures"])

    # Pin the runner image on the command line (overrides any ~/.actrc), use
    # the locally-present pwsh image, and `--pull=false` to avoid a registry
    # round-trip; `--rm` cleans up containers afterwards.
    proc = subprocess.run(
        [
            "act", "push", "--rm", "--pull=false",
            "-P", "ubuntu-latest=act-ubuntu-pwsh:latest",
        ],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=900,
    )
    output = proc.stdout + "\n" + proc.stderr
    # Persist BEFORE asserting so the artifact survives a failed assertion.
    _record(case["id"], proc.returncode, output)

    assert proc.returncode == 0, (
        f"act exited {proc.returncode} for case {case['id']}; see act-result.txt"
    )
    # Every job (3 matrix legs + 1 aggregate) must succeed, none may fail.
    assert "Job failed" not in output, f"a job failed for case {case['id']}"
    assert output.count("Job succeeded") >= 4, (
        f"expected >=4 'Job succeeded' for case {case['id']}, "
        f"got {output.count('Job succeeded')}"
    )
    # Exact aggregated values for this case's input.
    for needle in case["expect"]:
        assert needle in output, (
            f"expected '{needle}' in act output for case {case['id']}"
        )
    for needle in case["forbid"]:
        assert needle not in output, (
            f"did NOT expect '{needle}' in act output for case {case['id']}"
        )


def test_act_result_artifact_exists():
    """The act-result.txt artifact must exist after the act tests have run."""
    assert os.path.isfile(ACT_RESULT_FILE)
