"""End-to-end harness: every case runs through the real workflow via `act`.

For each case we build an isolated temp git repo containing the project files
plus that case's fixture data, run `act push --rm`, capture the output to
act-result.txt, and assert on the EXACT expected new version, a clean exit,
and that the job succeeded.

We keep to three representative cases (minor / major / no-release) to stay
within the act run budget; the per-function behaviour for the remaining
fixtures is already covered by the fast unit tests.
"""
import os
import shutil
import subprocess

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT_RESULT = os.path.join(ROOT, "act-result.txt")

# (case name, version file contents, fixture log, expected new version,
#  whether a bump should have happened)
CASES = [
    ("minor", "1.1.0\n", "minor.log", "1.2.0", True),
    ("major", "2.5.3\n", "major.log", "3.0.0", True),
    ("none", "3.2.1\n", "none.log", "3.2.1", False),
]


def _have_act():
    return shutil.which("act") is not None


pytestmark = pytest.mark.skipif(not _have_act(), reason="act not installed")


def _build_repo(tmp_path, version_text, fixture_name):
    """Create a self-contained git repo for one act run."""
    repo = tmp_path
    # Project files the workflow needs.
    shutil.copy(os.path.join(ROOT, "bump_version.py"), repo / "bump_version.py")
    wf_dir = repo / ".github" / "workflows"
    wf_dir.mkdir(parents=True)
    shutil.copy(
        os.path.join(ROOT, ".github", "workflows", "semantic-version-bumper.yml"),
        wf_dir / "semantic-version-bumper.yml",
    )
    # Reuse the repo's .actrc (maps ubuntu-latest to the prepared image).
    actrc = os.path.join(ROOT, ".actrc")
    if os.path.exists(actrc):
        shutil.copy(actrc, repo / ".actrc")

    # This case's fixture data.
    (repo / "VERSION").write_text(version_text)
    shutil.copy(
        os.path.join(ROOT, "tests", "fixtures", fixture_name), repo / "commits.log"
    )

    # act needs a real git repo with at least one commit.
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True, env=env)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True, env=env)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=repo, check=True, env=env)
    return repo


def _run_act(repo):
    # --pull=false: the mapped image is built locally and not in any registry,
    # so we must stop act from force-pulling it.
    return subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=repo,
        capture_output=True,
        text=True,
    )


@pytest.fixture(scope="module", autouse=True)
def _fresh_result_file():
    # Start with an empty artifact for this harness run.
    open(ACT_RESULT, "w").close()
    yield


@pytest.mark.parametrize("name,version_text,fixture,expected,bumped", CASES)
def test_workflow_via_act(tmp_path, name, version_text, fixture, expected, bumped):
    repo = _build_repo(tmp_path, version_text, fixture)
    result = _run_act(repo)

    # Append clearly-delimited output for this case to the required artifact.
    with open(ACT_RESULT, "a", encoding="utf-8") as fh:
        fh.write(f"\n{'=' * 70}\nCASE: {name} (expect {expected}, bumped={bumped})\n")
        fh.write(f"act exit code: {result.returncode}\n{'=' * 70}\n")
        fh.write(result.stdout)
        fh.write("\n--- STDERR ---\n")
        fh.write(result.stderr)

    combined = result.stdout + result.stderr

    # 1. act must exit cleanly.
    assert result.returncode == 0, f"act failed for {name}:\n{combined}"
    # 2. Every job must report success.
    assert "Job succeeded" in combined, f"no job success for {name}:\n{combined}"
    # 3. Exact expected version surfaced by the script.
    assert f"NEW_VERSION={expected}" in combined, (
        f"expected NEW_VERSION={expected} for {name}:\n{combined}"
    )
    # 4. Output step echoes the computed version exactly.
    assert f"Computed version: {expected}" in combined
