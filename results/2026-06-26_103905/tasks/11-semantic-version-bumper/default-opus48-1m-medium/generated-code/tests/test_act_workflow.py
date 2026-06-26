"""
End-to-end test harness: every test case runs through the real GitHub Actions
workflow via `act` (nektos/act), never against the script directly.

For each fixture case the harness:
  1. Builds an isolated temp git repo containing the project files
     (version_bumper.py, the workflow, .actrc) plus that case's fixture data
     (a VERSION or package.json and a commits.txt).
  2. Runs `act push --rm` and captures combined stdout/stderr.
  3. Appends the captured output to act-result.txt (delimited per case).
  4. Asserts act exited 0, the job "succeeded", and the EXACT expected
     new version / changelog content appears in the output.

Run just this file with:  python3 -m pytest tests/test_act_workflow.py -v -s
It is marked `act` / `slow`; the default `pytest tests/` run executes the fast
unit tests plus this harness. Skips cleanly if act or docker is unavailable.
"""

import os
import shutil
import subprocess
import textwrap

import pytest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT_FILE = os.path.join(PROJECT_ROOT, "act-result.txt")


# Each case: a fixture directory + the exact values we expect the pipeline to
# produce. These are known-good results computed by hand from the fixture input.
CASES = [
    {
        "name": "feat-minor",
        "expect_new_version": "1.2.0",
        "expect_old_version": "1.1.0",
        "expect_bump": "minor",
        "changelog_must_contain": ["## 1.2.0", "add user profile page"],
    },
    {
        "name": "fix-patch",
        "expect_new_version": "2.5.10",
        "expect_old_version": "2.5.9",
        "expect_bump": "patch",
        "changelog_must_contain": ["## 2.5.10", "prevent crash on null token"],
    },
    {
        "name": "breaking-major",
        "expect_new_version": "1.0.0",
        "expect_old_version": "0.9.3",
        "expect_bump": "major",
        "changelog_must_contain": ["## 1.0.0", "remove deprecated v1 API"],
    },
    {
        "name": "no-release",
        "expect_new_version": "4.2.0",
        "expect_old_version": "4.2.0",
        "expect_bump": "None",
        "changelog_must_contain": [],
    },
    {
        "name": "pkgjson-feat",
        "expect_new_version": "3.1.0",
        "expect_old_version": "3.0.0",
        "expect_bump": "minor",
        "changelog_must_contain": ["## 3.1.0", "support bulk export"],
    },
]


def _have(tool: str) -> bool:
    return shutil.which(tool) is not None


pytestmark = pytest.mark.skipif(
    not (_have("act") and _have("docker")),
    reason="act and/or docker not available",
)


def _setup_repo(work: str, case_name: str) -> None:
    """Populate `work` with the project files plus this case's fixtures."""
    # Project files needed inside the container.
    shutil.copy(os.path.join(PROJECT_ROOT, "version_bumper.py"), work)
    os.makedirs(os.path.join(work, ".github", "workflows"), exist_ok=True)
    shutil.copy(
        os.path.join(PROJECT_ROOT, ".github", "workflows", "semantic-version-bumper.yml"),
        os.path.join(work, ".github", "workflows"),
    )
    actrc = os.path.join(PROJECT_ROOT, ".actrc")
    if os.path.exists(actrc):
        shutil.copy(actrc, work)

    # This case's fixture data (VERSION or package.json + commits.txt).
    fixture_dir = os.path.join(PROJECT_ROOT, "fixtures", case_name)
    for fname in os.listdir(fixture_dir):
        shutil.copy(os.path.join(fixture_dir, fname), work)

    # act needs an actual git repo with a commit to run `push`.
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=work, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=work, check=True, env=env)
    subprocess.run(["git", "commit", "-q", "-m", "fixture"], cwd=work, check=True, env=env)


def _run_act(work: str) -> subprocess.CompletedProcess:
    """Invoke `act push --rm` and return the completed process."""
    return subprocess.run(
        # --pull=false: use the locally-built act image instead of pulling.
        ["act", "push", "--rm", "--pull=false",
         "-W", ".github/workflows/semantic-version-bumper.yml"],
        cwd=work,
        capture_output=True,
        text=True,
        timeout=600,
    )


def _append_result(case_name: str, proc: subprocess.CompletedProcess) -> None:
    with open(ACT_RESULT_FILE, "a", encoding="utf-8") as fh:
        fh.write("\n" + "=" * 78 + "\n")
        fh.write(f"TEST CASE: {case_name}  (act exit={proc.returncode})\n")
        fh.write("=" * 78 + "\n")
        fh.write("----- STDOUT -----\n")
        fh.write(proc.stdout)
        fh.write("\n----- STDERR -----\n")
        fh.write(proc.stderr)
        fh.write("\n")


@pytest.fixture(scope="module", autouse=True)
def _reset_result_file():
    # Start each harness run with a fresh, header-stamped artifact file.
    with open(ACT_RESULT_FILE, "w", encoding="utf-8") as fh:
        fh.write("act-result.txt -- output of every test case run through `act push`\n")
    yield


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_case_through_act(case, tmp_path):
    work = str(tmp_path / case["name"])
    os.makedirs(work, exist_ok=True)
    _setup_repo(work, case["name"])

    proc = _run_act(work)
    _append_result(case["name"], proc)

    combined = proc.stdout + "\n" + proc.stderr

    # 1. act must exit cleanly.
    assert proc.returncode == 0, (
        f"act exited {proc.returncode} for {case['name']}:\n{combined[-3000:]}"
    )

    # 2. The job must report success.
    assert "Job succeeded" in combined, (
        f"no 'Job succeeded' for {case['name']}:\n{combined[-3000:]}"
    )

    # 3. EXACT expected values must appear in the workflow output.
    assert f"NEW_VERSION={case['expect_new_version']}" in combined, (
        f"expected NEW_VERSION={case['expect_new_version']} for {case['name']}:\n"
        f"{combined[-3000:]}"
    )
    assert f"OLD_VERSION={case['expect_old_version']}" in combined
    assert f"BUMP={case['expect_bump']}" in combined
    assert f"Next version is: {case['expect_new_version']}" in combined

    # 4. Changelog content (when a release happened).
    for needle in case["changelog_must_contain"]:
        assert needle in combined, (
            f"expected changelog content {needle!r} for {case['name']}:\n"
            f"{combined[-3000:]}"
        )


def test_act_result_artifact_exists():
    # The act-result.txt artifact must exist and contain every case.
    assert os.path.exists(ACT_RESULT_FILE)
    content = open(ACT_RESULT_FILE, encoding="utf-8").read()
    for case in CASES:
        assert f"TEST CASE: {case['name']}" in content
