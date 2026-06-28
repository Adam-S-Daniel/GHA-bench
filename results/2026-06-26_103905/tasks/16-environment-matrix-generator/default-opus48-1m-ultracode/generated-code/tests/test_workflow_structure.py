"""
Workflow *structure* tests (fast, no act required).

These parse the workflow YAML and assert its shape: triggers, jobs, steps, the
permissions block, that it references our script and fixtures by their real
paths, and that actionlint passes cleanly.
"""

import subprocess
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = PROJECT_ROOT / ".github" / "workflows" / "environment-matrix-generator.yml"
SCRIPT = PROJECT_ROOT / "matrix_generator.py"
FIXTURES = PROJECT_ROOT / "tests" / "fixtures"


def _load_workflow():
    return yaml.safe_load(WORKFLOW.read_text())


def _triggers(cfg):
    # PyYAML parses the bare key `on:` as the boolean True (YAML 1.1), which is
    # the classic GitHub Actions gotcha -- handle both spellings.
    return cfg.get("on", cfg.get(True))


# --- file presence -------------------------------------------------------

def test_workflow_file_exists():
    assert WORKFLOW.is_file()


def test_script_file_exists():
    assert SCRIPT.is_file()


def test_all_fixtures_exist():
    for name in ("basic", "exclude", "include", "full", "oversized"):
        assert (FIXTURES / f"{name}.json").is_file(), name


# --- YAML / structure ----------------------------------------------------

def test_workflow_is_valid_yaml():
    cfg = _load_workflow()
    assert isinstance(cfg, dict)
    assert cfg["name"] == "Environment Matrix Generator"


def test_workflow_has_expected_triggers():
    triggers = _triggers(_load_workflow())
    assert isinstance(triggers, dict)
    for event in ("push", "pull_request", "schedule", "workflow_dispatch"):
        assert event in triggers, f"missing trigger: {event}"
    # schedule must carry a cron entry
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"
    # workflow_dispatch exposes a config_file input
    assert "config_file" in triggers["workflow_dispatch"]["inputs"]


def test_workflow_declares_least_privilege_permissions():
    cfg = _load_workflow()
    assert cfg["permissions"]["contents"] == "read"


def test_workflow_defines_default_config_env():
    cfg = _load_workflow()
    assert cfg["env"]["CONFIG_FILE"] == "matrix-config.json"


def test_jobs_present():
    jobs = _load_workflow()["jobs"]
    assert "generate-matrix" in jobs
    assert "build" in jobs


def test_generate_job_runs_our_script_and_checks_out():
    gen = _load_workflow()["jobs"]["generate-matrix"]
    steps = gen["steps"]
    # actions/checkout@v4 is used
    assert any(s.get("uses") == "actions/checkout@v4" for s in steps)
    # the script is invoked by its real filename
    run_blob = "\n".join(s.get("run", "") for s in steps)
    assert "matrix_generator.py" in run_blob
    assert "--github-output" in run_blob
    # the script the workflow names must actually exist
    assert SCRIPT.is_file()


def test_generate_job_exposes_matrix_outputs():
    gen = _load_workflow()["jobs"]["generate-matrix"]
    for out in ("matrix", "size", "valid"):
        assert out in gen["outputs"], out


def test_build_job_depends_on_generate_and_uses_dynamic_matrix():
    build = _load_workflow()["jobs"]["build"]
    assert build["needs"] == "generate-matrix"
    # gated on validation passing
    assert "needs.generate-matrix.outputs.valid == 'true'" in build["if"]
    # dynamic matrix consumed from the upstream job output
    matrix_expr = build["strategy"]["matrix"]
    assert "fromJSON" in matrix_expr
    assert "needs.generate-matrix.outputs.matrix" in matrix_expr


# --- actionlint ----------------------------------------------------------

def test_actionlint_passes():
    proc = subprocess.run(
        ["actionlint", str(WORKFLOW)],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"actionlint failed:\n{proc.stdout}\n{proc.stderr}"
