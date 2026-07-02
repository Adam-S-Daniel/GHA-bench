"""
Structural / static tests for the GitHub Actions workflow itself: parse the
YAML and assert on triggers/jobs/steps, confirm every file path the workflow
references actually exists in the repo, and confirm `actionlint` passes.

This is separate from tests/test_workflow_via_act.py, which actually
*executes* the workflow in Docker via `act` and checks its real output.
"""
import subprocess
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "semantic-version-bumper.yml"


def _load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        # YAML parses the bare "on:" key as the boolean True, not the string
        # "on" -- PyYAML's 1.1 boolean resolution kicks in here. Look it up
        # by whichever key shows up.
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert WORKFLOW_PATH.is_file(), f"Expected workflow at {WORKFLOW_PATH}"


def test_workflow_has_expected_triggers():
    doc = _load_workflow()
    triggers = doc.get("on", doc.get(True))
    assert triggers is not None, "workflow has no 'on:' triggers"
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers
    assert "schedule" in triggers


def test_workflow_has_bump_version_job_with_matrix():
    doc = _load_workflow()
    jobs = doc["jobs"]
    assert "bump-version" in jobs
    job = jobs["bump-version"]
    cases = job["strategy"]["matrix"]["case"]
    assert len(cases) == 6
    case_names = {c["name"] for c in cases}
    assert case_names == {
        "feat-bump", "fix-bump", "breaking-bump",
        "mixed-precedence", "package-json-bump", "no-bump",
    }


def test_workflow_uses_checkout_action():
    doc = _load_workflow()
    steps = doc["jobs"]["bump-version"]["steps"]
    uses_steps = [s["uses"] for s in steps if "uses" in s]
    assert any(u.startswith("actions/checkout@") for u in uses_steps)


def test_workflow_references_version_bumper_script():
    doc = _load_workflow()
    steps = doc["jobs"]["bump-version"]["steps"]
    run_text = "\n".join(s.get("run", "") for s in steps)
    assert "version_bumper.py" in run_text


def test_referenced_script_path_exists():
    assert (REPO_ROOT / "version_bumper.py").is_file()


def test_referenced_fixture_paths_exist():
    doc = _load_workflow()
    cases = doc["jobs"]["bump-version"]["strategy"]["matrix"]["case"]
    for case in cases:
        assert (REPO_ROOT / case["version_file"]).is_file(), case["version_file"]
        assert (REPO_ROOT / case["commits_file"]).is_file(), case["commits_file"]


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", str(WORKFLOW_PATH)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"actionlint failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
