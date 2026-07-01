"""
Static structure tests for the GitHub Actions workflow file. These validate
the YAML shape and tooling (actionlint) directly on the host -- they are
distinct from the label-assignment *behavior* tests in
test_label_assigner.py, which are exercised end-to-end through the workflow
itself via `act` (see run_act_tests.py / act-result.txt).
"""
import os
import subprocess

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "pr-label-assigner.yml")


def load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_has_expected_triggers():
    workflow = load_workflow()
    # YAML parses the bare key `on` as the boolean True, not the string "on".
    triggers = workflow.get("on") or workflow.get(True)
    assert triggers is not None
    assert "push" in triggers
    assert "pull_request" in triggers
    assert "workflow_dispatch" in triggers


def test_workflow_has_expected_jobs_and_dependency():
    workflow = load_workflow()
    jobs = workflow["jobs"]
    assert "test" in jobs
    assert "assign-labels" in jobs
    # assign-labels must depend on test (job dependency requirement).
    assert jobs["assign-labels"]["needs"] == "test"


def test_workflow_jobs_have_steps():
    workflow = load_workflow()
    for job in workflow["jobs"].values():
        assert len(job["steps"]) > 0


def test_workflow_has_permissions_block():
    workflow = load_workflow()
    assert "permissions" in workflow
    assert workflow["permissions"]["contents"] == "read"


def test_workflow_references_existing_script_files():
    workflow = load_workflow()
    all_run_text = ""
    for job in workflow["jobs"].values():
        for step in job["steps"]:
            all_run_text += step.get("run", "") + "\n"

    assert "label_assigner.py" in all_run_text
    assert os.path.isfile(os.path.join(REPO_ROOT, "label_assigner.py"))

    assert "$RULES_FILE" in all_run_text
    rules_file = workflow["env"]["RULES_FILE"]
    assert os.path.isfile(os.path.join(REPO_ROOT, rules_file))

    # Every referenced fixture file must actually exist on disk.
    for fixture in ("fixtures/pr_docs_only.json", "fixtures/pr_api_change.json",
                    "fixtures/pr_mixed.json", "fixtures/pr_no_match.json"):
        assert fixture in all_run_text
        assert os.path.isfile(os.path.join(REPO_ROOT, fixture))


def test_actionlint_passes():
    result = subprocess.run(
        ["actionlint", WORKFLOW_PATH],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"actionlint failed:\n{result.stdout}\n{result.stderr}"
