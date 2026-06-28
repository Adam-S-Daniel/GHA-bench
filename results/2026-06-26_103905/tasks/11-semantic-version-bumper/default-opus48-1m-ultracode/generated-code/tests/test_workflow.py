"""Workflow *structure* tests.

These do not run anything in Docker; they statically verify that the workflow
YAML has the shape we expect, references the script + fixtures that actually
exist on disk, and passes ``actionlint`` (exit code 0). The behavioural,
runs-in-a-container checks live in ``tests/test_act_integration.py``.
"""

import os
import shutil
import subprocess

import pytest
import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(PROJECT_ROOT, ".github", "workflows", "semantic-version-bumper.yml")

EXPECTED_SCENARIOS = {"feat", "fix", "breaking", "package-json", "no-bump"}


@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(data):
    # PyYAML parses the bare key ``on`` as the boolean True (YAML 1.1), so the
    # triggers may live under either the string "on" or the boolean True.
    return data.get("on", data.get(True))


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH), f"missing workflow at {WORKFLOW_PATH}"


def test_workflow_is_valid_yaml(workflow):
    assert isinstance(workflow, dict)
    assert workflow.get("name") == "Semantic Version Bumper"


def test_workflow_has_expected_triggers(workflow):
    triggers = _triggers(workflow)
    assert isinstance(triggers, dict)
    # Exercise a realistic mix of trigger events.
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"trigger {event!r} missing"


def test_workflow_has_top_level_permissions(workflow):
    assert workflow.get("permissions", {}).get("contents") == "read"


def test_workflow_defines_both_jobs(workflow):
    jobs = workflow["jobs"]
    assert "validate" in jobs
    assert "release" in jobs


def test_validate_job_matrix_covers_all_scenarios(workflow):
    matrix = workflow["jobs"]["validate"]["strategy"]["matrix"]
    assert set(matrix["scenario"]) == EXPECTED_SCENARIOS


def test_release_job_depends_on_validate(workflow):
    # Job dependency requirement.
    assert workflow["jobs"]["release"]["needs"] == "validate"


def test_release_job_has_write_permission(workflow):
    assert workflow["jobs"]["release"]["permissions"]["contents"] == "write"


def test_jobs_checkout_with_v4(workflow):
    for job_name in ("validate", "release"):
        steps = workflow["jobs"][job_name]["steps"]
        uses = [s.get("uses", "") for s in steps]
        assert any(u == "actions/checkout@v4" for u in uses), \
            f"{job_name} must check out with actions/checkout@v4"


def test_workflow_references_the_script(workflow):
    # Every job that does work must invoke version_bumper.py.
    text = "\n".join(
        s.get("run", "")
        for job in workflow["jobs"].values()
        for s in job["steps"]
    )
    assert "version_bumper.py" in text


def test_referenced_script_and_fixtures_exist_on_disk():
    # The paths the workflow references must actually be present.
    assert os.path.isfile(os.path.join(PROJECT_ROOT, "version_bumper.py"))
    assert os.path.isfile(os.path.join(PROJECT_ROOT, "VERSION"))
    assert os.path.isfile(os.path.join(PROJECT_ROOT, "commits.txt"))
    for scenario in EXPECTED_SCENARIOS:
        d = os.path.join(PROJECT_ROOT, "fixtures", scenario)
        assert os.path.isdir(d), f"fixture dir missing: {d}"
        assert os.path.isfile(os.path.join(d, "commits.txt"))
        has_version = os.path.isfile(os.path.join(d, "VERSION"))
        has_pkg = os.path.isfile(os.path.join(d, "package.json"))
        assert has_version or has_pkg, f"{scenario} needs a VERSION or package.json"


@pytest.mark.skipif(shutil.which("actionlint") is None, reason="actionlint not installed")
def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", WORKFLOW_PATH],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, (
        f"actionlint failed:\n{result.stdout}\n{result.stderr}"
    )
