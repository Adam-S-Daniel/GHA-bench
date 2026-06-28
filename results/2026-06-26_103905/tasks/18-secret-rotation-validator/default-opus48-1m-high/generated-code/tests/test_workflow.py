"""Workflow tests.

Two layers:

1. **Structure tests** (fast, pure): parse the workflow YAML and assert it has
   the expected triggers / jobs / steps, references files that actually exist,
   and passes ``actionlint``.

2. **Act integration test** (slow): every functional test case is executed
   *through the GitHub Actions pipeline* using ``act`` (nektos/act) in Docker —
   not against the script directly. For each case we build a throwaway git
   repo containing the project plus that case's fixture (written to the
   workflow's default config path), run ``act push --rm``, and assert on the
   exact summary line the workflow prints. All act output is appended to
   ``act-result.txt`` in the project directory.
"""
import os
import shutil
import subprocess

import pytest
import yaml

# Project root = parent of this tests/ directory.
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_PATH = os.path.join(
    PROJECT_ROOT, ".github", "workflows", "secret-rotation-validator.yml"
)
SCRIPT_PATH = os.path.join(PROJECT_ROOT, "secret_rotation_validator.py")
ACT_RESULT = os.path.join(PROJECT_ROOT, "act-result.txt")

# A fixed reference date so every act run is deterministic.
NOW_DATE = "2026-06-27"

# Each case: (label, fixture filename, exact expected summary line).
# The expected values were verified against the script with --now 2026-06-27
# and the default 14-day warning window.
ACT_CASES = [
    ("mixed", "mixed.json",
     "ROTATION_SUMMARY expired=1 warning=1 ok=1 total=3"),
    ("all_ok", "all_ok.json",
     "ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2"),
    ("all_expired", "all_expired.json",
     "ROTATION_SUMMARY expired=2 warning=0 ok=0 total=2"),
]


# ---------------------------------------------------------------------------
# Structure tests
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module")
def workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _triggers(workflow):
    # PyYAML parses the bare key `on:` as the boolean True, so accept either.
    return workflow.get("on", workflow.get(True))


def test_workflow_file_exists():
    assert os.path.isfile(WORKFLOW_PATH)


def test_workflow_has_expected_triggers(workflow):
    triggers = _triggers(workflow)
    assert isinstance(triggers, dict)
    for event in ("push", "pull_request", "workflow_dispatch", "schedule"):
        assert event in triggers, f"missing trigger: {event}"
    # The schedule must carry a cron expression.
    assert triggers["schedule"][0]["cron"] == "0 8 * * 1"


def test_workflow_has_least_privilege_permissions(workflow):
    assert workflow["permissions"] == {"contents": "read"}


def test_workflow_has_validate_job_on_ubuntu(workflow):
    jobs = workflow["jobs"]
    assert "validate" in jobs
    assert jobs["validate"]["runs-on"] == "ubuntu-latest"


def test_workflow_checks_out_and_runs_script(workflow):
    steps = workflow["jobs"]["validate"]["steps"]
    uses = [s.get("uses", "") for s in steps]
    runs = "\n".join(s.get("run", "") for s in steps)
    assert any(u.startswith("actions/checkout@v4") for u in uses)
    # The workflow must actually invoke our script.
    assert "secret_rotation_validator.py" in runs


def test_workflow_references_existing_files():
    # The script the workflow runs must exist on disk.
    assert os.path.isfile(SCRIPT_PATH)
    # The default config path referenced by the workflow env must exist.
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as fh:
        wf = yaml.safe_load(fh)
    config_default = wf["env"]["CONFIG_FILE"]
    assert os.path.isfile(os.path.join(PROJECT_ROOT, config_default)), config_default


def test_actionlint_passes():
    actionlint = shutil.which("actionlint")
    assert actionlint, "actionlint must be installed"
    proc = subprocess.run(
        [actionlint, WORKFLOW_PATH],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"


# ---------------------------------------------------------------------------
# Act integration test — every functional case runs through the pipeline.
# ---------------------------------------------------------------------------
def _have(cmd):
    return shutil.which(cmd) is not None


def _setup_repo(workdir, fixture_name):
    """Create a self-contained git repo with the project + this case's fixture."""
    # Copy the script and the workflow tree.
    shutil.copy(SCRIPT_PATH, os.path.join(workdir, "secret_rotation_validator.py"))
    shutil.copytree(
        os.path.join(PROJECT_ROOT, ".github"),
        os.path.join(workdir, ".github"),
    )
    # Reuse the same act runner image mapping the project uses.
    actrc = os.path.join(PROJECT_ROOT, ".actrc")
    if os.path.isfile(actrc):
        shutil.copy(actrc, os.path.join(workdir, ".actrc"))

    # Write this case's fixture to the workflow's DEFAULT config path so we do
    # not have to override CONFIG_FILE (workflow-level env would win over
    # `act --env` anyway). Only NOW_DATE is injected via the environment.
    os.makedirs(os.path.join(workdir, "fixtures"), exist_ok=True)
    shutil.copy(
        os.path.join(PROJECT_ROOT, "fixtures", fixture_name),
        os.path.join(workdir, "fixtures", "default.json"),
    )

    # act requires a committed git repo.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=workdir, check=True, env=env)
    subprocess.run(["git", "config", "user.email", "ci@example.com"], cwd=workdir, check=True)
    subprocess.run(["git", "config", "user.name", "ci"], cwd=workdir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=workdir, check=True, env=env)
    subprocess.run(
        ["git", "commit", "-q", "-m", "fixture"], cwd=workdir, check=True, env=env
    )


@pytest.mark.skipif(
    not (_have("act") and _have("docker")),
    reason="act and docker are required for the pipeline integration test",
)
def test_all_cases_run_through_act(tmp_path):
    """Run every case through `act push` and assert on exact pipeline output."""
    # Start with a fresh result artifact for this run.
    with open(ACT_RESULT, "w", encoding="utf-8") as fh:
        fh.write("# Secret Rotation Validator — act execution log\n")

    failures = []
    for label, fixture, expected_summary in ACT_CASES:
        workdir = str(tmp_path / label)
        os.makedirs(workdir, exist_ok=True)
        _setup_repo(workdir, fixture)

        proc = subprocess.run(
            [
                "act", "push", "--rm",
                # Use the locally-built runner image; never try to pull it.
                "--pull=false",
                "--env", f"NOW_DATE={NOW_DATE}",
                "-W", ".github/workflows/secret-rotation-validator.yml",
            ],
            cwd=workdir, capture_output=True, text=True,
        )
        output = proc.stdout + "\n" + proc.stderr

        # Append this case's full output, clearly delimited.
        with open(ACT_RESULT, "a", encoding="utf-8") as fh:
            fh.write("\n" + "=" * 78 + "\n")
            fh.write(f"CASE: {label} (fixture={fixture}, now={NOW_DATE})\n")
            fh.write(f"expected: {expected_summary}\n")
            fh.write(f"act exit code: {proc.returncode}\n")
            fh.write("=" * 78 + "\n")
            fh.write(output)

        # Collect assertions (don't abort early — we want all cases logged).
        if proc.returncode != 0:
            failures.append(f"[{label}] act exit {proc.returncode}")
        if expected_summary not in output:
            failures.append(f"[{label}] missing summary: {expected_summary!r}")
        if "Job succeeded" not in output:
            failures.append(f"[{label}] no 'Job succeeded' marker")

    assert os.path.isfile(ACT_RESULT)
    assert not failures, "act pipeline assertions failed:\n" + "\n".join(failures)
