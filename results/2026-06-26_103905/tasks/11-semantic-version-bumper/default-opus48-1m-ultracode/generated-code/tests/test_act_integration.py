"""End-to-end pipeline tests — every test case runs *through the workflow* via
``act`` (nektos/act) in a real Docker container.

Strategy (and why it stays within the act-run budget):
The workflow's ``validate`` job is a build matrix over all five release
scenarios, so a *single* ``act push`` exercises every test case in one go. We
therefore run act exactly once (a module-scoped fixture), capture the full
output to ``act-result.txt``, and then make exact-value assertions per scenario
against that captured output. Re-running act per scenario would be wasteful and
blow the "limit act runs" budget for no extra coverage.

What we assert (per the task spec):
  * act exited 0
  * each scenario produced its EXACT expected next version
  * the release job produced its EXACT expected next version
  * every job reports "Job succeeded"
  * ``act-result.txt`` exists as a required artifact
"""

import os
import shutil
import subprocess

import pytest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT = os.path.join(PROJECT_ROOT, "act-result.txt")

# Known-good expected next versions for each fixture scenario.
EXPECTED_SCENARIOS = {
    "feat": "1.2.0",          # 1.1.0 + feat  -> minor
    "fix": "1.1.1",           # 1.1.0 + fix   -> patch
    "breaking": "2.0.0",      # 1.1.0 + feat! -> major
    "package-json": "0.6.0",  # 0.5.2 + feat  -> minor (package.json source)
    "no-bump": "2.3.4",       # no release commits -> unchanged
}
EXPECTED_RELEASE = "1.1.0"    # repo VERSION 1.0.0 + feat -> minor
EXPECTED_JOB_COUNT = len(EXPECTED_SCENARIOS) + 1  # 5 matrix jobs + 1 release

# Files / directories copied into the throwaway git repo act runs against.
PROJECT_FILES = ["version_bumper.py", "VERSION", "commits.txt", "CHANGELOG.md", ".actrc"]
PROJECT_DIRS = [".github", "fixtures"]

requires_act = pytest.mark.skipif(
    shutil.which("act") is None or shutil.which("docker") is None,
    reason="act and docker are required for the pipeline integration test",
)


def _git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True,
                   capture_output=True, text=True)


def _write_result_file(returncode, output):
    """Persist the act run to the required ``act-result.txt`` artifact, with a
    clearly delimited section per scenario summarising the parsed result."""
    lines = []
    lines.append("=" * 78)
    lines.append("ACT RUN: semantic-version-bumper workflow (all scenarios, single push)")
    lines.append(f"act exit code: {returncode}")
    lines.append("=" * 78)
    lines.append(output)
    lines.append("")
    lines.append("=" * 78)
    lines.append("PARSED PER-TEST-CASE RESULTS (asserted by the harness)")
    lines.append("=" * 78)
    for scenario, expected in EXPECTED_SCENARIOS.items():
        marker = f"RESULT scenario={scenario} new_version={expected}"
        status = "OK" if marker in output else "MISSING"
        lines.append(f"--- test case: {scenario} ---")
        lines.append(f"expected new_version={expected} -> {status}")
    rel_marker = f"RELEASE_NEW_VERSION={EXPECTED_RELEASE}"
    lines.append("--- test case: release ---")
    lines.append(f"expected RELEASE_NEW_VERSION={EXPECTED_RELEASE} -> "
                 f"{'OK' if rel_marker in output else 'MISSING'}")
    succeeded = output.count("Job succeeded")
    lines.append("")
    lines.append(f"'Job succeeded' occurrences: {succeeded} "
                 f"(expected >= {EXPECTED_JOB_COUNT})")
    with open(ACT_RESULT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


@pytest.fixture(scope="module")
def act_run(tmp_path_factory):
    """Set up an isolated git repo with the project + fixtures, run the
    workflow once through ``act push``, capture output to ``act-result.txt``,
    and return ``(returncode, combined_output)``."""
    repo = tmp_path_factory.mktemp("svb_act_repo")

    for name in PROJECT_FILES:
        shutil.copy(os.path.join(PROJECT_ROOT, name), os.path.join(repo, name))
    for name in PROJECT_DIRS:
        shutil.copytree(os.path.join(PROJECT_ROOT, name), os.path.join(repo, name))

    # A push event needs a git repo on a branch the workflow listens to (main).
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "tester@example.com")
    _git(repo, "config", "user.name", "Pipeline Tester")
    _git(repo, "symbolic-ref", "HEAD", "refs/heads/main")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "test: set up fixture repo")

    # --pull=false: use the locally-built act image named in .actrc rather than
    # trying to pull it from a registry. --rm cleans up the container.
    cmd = ["act", "push", "--rm", "--pull=false"]
    output, returncode = "", 1
    try:
        proc = subprocess.run(cmd, cwd=str(repo), capture_output=True,
                              text=True, timeout=900)
        output = (proc.stdout or "") + "\n" + (proc.stderr or "")
        returncode = proc.returncode
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "") + "\n[act timed out after 900s]"
        returncode = 124
    finally:
        # Always write the artifact, even on failure/timeout.
        _write_result_file(returncode, output)

    return returncode, output


@requires_act
def test_act_exits_zero(act_run):
    returncode, output = act_run
    assert returncode == 0, f"act exited {returncode}; see act-result.txt"


@requires_act
def test_act_result_artifact_exists(act_run):
    # Required deliverable: the artifact file must exist and be non-empty.
    assert os.path.isfile(ACT_RESULT)
    assert os.path.getsize(ACT_RESULT) > 0


@requires_act
@pytest.mark.parametrize("scenario,expected", sorted(EXPECTED_SCENARIOS.items()))
def test_scenario_produces_exact_version(act_run, scenario, expected):
    _, output = act_run
    marker = f"RESULT scenario={scenario} new_version={expected}"
    assert marker in output, (
        f"expected exact line {marker!r} in act output for scenario "
        f"{scenario!r}; see act-result.txt"
    )


@requires_act
def test_release_job_produces_exact_version(act_run):
    _, output = act_run
    assert f"RELEASE_NEW_VERSION={EXPECTED_RELEASE}" in output, \
        "release job did not output the expected new version; see act-result.txt"
    # The release job also writes the version file in-container.
    assert "RELEASE_BUMP_TYPE=minor" in output


@requires_act
def test_every_job_succeeded(act_run):
    _, output = act_run
    assert "Job failed" not in output, "a job failed; see act-result.txt"
    succeeded = output.count("Job succeeded")
    assert succeeded >= EXPECTED_JOB_COUNT, (
        f"expected at least {EXPECTED_JOB_COUNT} 'Job succeeded' markers, "
        f"found {succeeded}; see act-result.txt"
    )
