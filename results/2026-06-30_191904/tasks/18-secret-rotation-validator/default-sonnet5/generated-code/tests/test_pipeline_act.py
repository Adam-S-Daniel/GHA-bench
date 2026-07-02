"""
Pipeline acceptance tests.

Per the task's testing rules, the validator's *behavior* must be exercised
through the real GitHub Actions pipeline (via `act`), not by importing or
subprocess-invoking the script directly. Each test case here:

  1. Creates a fresh temp directory and copies the project files into it
     (script, workflow, fixtures, .actrc so `act` uses the pre-built runner
     image instead of trying to pull one from the network).
  2. Overwrites fixtures/secrets-config.json with that case's fixture data
     (or removes it, for the missing-config case).
  3. `git init`s a throwaway repo there, commits, and runs `act push --rm`.
  4. Appends the full output to act-result.txt (in the *original* working
     directory, not the temp dir) under a clearly delimited header.
  5. Asserts on exact expected values computed against the fixed reference
     date the workflow uses (2026-07-01) -- exact secret names, exact
     "days remaining" / "days ago" counts, and exact summary counts, plus
     the exit code and "Job succeeded" / "Job failed" markers.

Three scenarios exercise the full urgency-grouping + dual-format behavior:
  - "mixed": one expired, one warning, one ok secret, plus one malformed
    entry that must be skipped with a warning (not crash the report).
  - "healthy": all secrets ok, zero expired/warning -- exercises the empty
    group ("_None_") rendering and the JSON format end to end.
  - "missing_config": the config file itself is absent. There is nothing to
    report on, so this is the one scenario where the job is expected to
    fail (non-zero exit) with a clear error message -- this is the
    deliberate exception to "exit 0" and is asserted as such below.
"""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
ACT_RESULT_PATH = REPO_ROOT / "act-result.txt"

PROJECT_FILES = [
    "secret_rotation_validator.py",
    ".github",
    "fixtures",
    ".actrc",
]

MIXED_CONFIG = {
    "warning_days": 14,
    "secrets": [
        {
            "name": "DB_PASSWORD",
            "last_rotated": "2026-01-01",
            "rotation_days": 90,
            "required_by": ["api-service", "worker"],
        },
        {
            "name": "API_KEY",
            "last_rotated": "2026-06-10",
            "rotation_days": 30,
            "required_by": ["payment-service"],
        },
        {
            "name": "TLS_CERT",
            "last_rotated": "2026-01-15",
            "rotation_days": 365,
            "required_by": ["web-frontend", "load-balancer"],
        },
        {
            # Deliberately malformed: no "rotation_days". Must be skipped
            # with a warning, not crash the whole report.
            "name": "BROKEN_SECRET",
            "last_rotated": "2026-01-01",
            "required_by": ["legacy-service"],
        },
    ],
}

HEALTHY_CONFIG = {
    "warning_days": 14,
    "secrets": [
        {
            "name": "WEB_CERT",
            "last_rotated": "2026-06-20",
            "rotation_days": 90,
            "required_by": ["web-frontend"],
        },
        {
            "name": "SSH_KEY",
            "last_rotated": "2026-05-01",
            "rotation_days": 180,
            "required_by": ["deploy-bot"],
        },
    ],
}


@pytest.fixture(scope="module", autouse=True)
def _fresh_act_result_file():
    """Start each full test run with a clean act-result.txt (no stale runs)."""
    if ACT_RESULT_PATH.exists():
        ACT_RESULT_PATH.unlink()
    yield


def _write_act_result(header: str, content: str) -> None:
    """Append one test case's act output to act-result.txt, clearly delimited."""
    with open(ACT_RESULT_PATH, "a") as f:
        f.write(f"\n{'=' * 80}\n{header}\n{'=' * 80}\n")
        f.write(content)
        f.write("\n")


def _run_act_case(tmp_path: Path, case_name: str, config_data) -> subprocess.CompletedProcess:
    """Set up an isolated temp git repo for one fixture case and run `act push --rm`."""
    work_dir = tmp_path / case_name
    work_dir.mkdir()

    for name in PROJECT_FILES:
        src = REPO_ROOT / name
        dst = work_dir / name
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)

    config_path = work_dir / "fixtures" / "secrets-config.json"
    if config_data is None:
        # The "missing config" scenario: remove the file entirely.
        config_path.unlink()
    else:
        config_path.write_text(json.dumps(config_data, indent=2))

    subprocess.run(["git", "init", "-q"], cwd=work_dir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=work_dir, check=True)
    subprocess.run(["git", "config", "user.name", "Test Harness"], cwd=work_dir, check=True)
    subprocess.run(["git", "add", "-A"], cwd=work_dir, check=True)
    subprocess.run(["git", "commit", "-q", "-m", f"test case: {case_name}"], cwd=work_dir, check=True)

    # --pull=false: act-ubuntu-pwsh:latest is a locally-built image that lives
    # in no registry. Without this, act force-pulls on every run and fails with
    # a Docker Hub auth error instead of using the image already on disk.
    result = subprocess.run(
        ["act", "push", "--rm", "--pull=false"],
        cwd=work_dir,
        capture_output=True,
        text=True,
        timeout=300,
    )

    _write_act_result(
        f"TEST CASE: {case_name}\nExit code: {result.returncode}",
        result.stdout + result.stderr,
    )
    return result


@pytest.fixture(scope="module")
def act_tmp_root(tmp_path_factory):
    return tmp_path_factory.mktemp("act-cases")


def test_mixed_secrets_case_produces_grouped_report(act_tmp_root):
    """Expired + warning + ok + one skipped malformed entry, in one act run."""
    result = _run_act_case(act_tmp_root, "mixed", MIXED_CONFIG)
    output = result.stdout + result.stderr

    assert result.returncode == 0, f"act push should succeed for a valid config:\n{output}"
    assert "Job succeeded" in output

    # Exact values computed against the workflow's fixed REFERENCE_DATE
    # (2026-07-01) with warning_days=14:
    #   DB_PASSWORD: last_rotated 2026-01-01 + 90d = 2026-04-01 -> 91 days ago -> expired
    #   API_KEY:     last_rotated 2026-06-10 + 30d = 2026-07-10 -> 9 days remaining -> warning
    #   TLS_CERT:    last_rotated 2026-01-15 + 365d = 2027-01-15 -> 198 days remaining -> ok
    assert "Summary: 1 expired, 1 warning, 1 ok (3 total)" in output
    assert "DB_PASSWORD" in output and "91 days ago" in output
    assert "API_KEY" in output and "| 9 |" in output
    assert "TLS_CERT" in output and "| 198 |" in output

    # The malformed entry must be reported, not silently dropped or fatal.
    assert "Secret 'BROKEN_SECRET' is missing a valid positive integer 'rotation_days'" in output

    # JSON format step must also run and reflect the same exact grouping.
    assert '"expired": 1' in output
    assert '"warning": 1' in output
    assert '"ok": 2' not in output  # sanity: summary.ok must be 1, not the group-list length
    assert '"total": 3' in output


def test_healthy_secrets_case_has_empty_expired_and_warning_groups(act_tmp_root):
    """All secrets healthy: zero expired/warning, empty-group rendering, JSON format."""
    result = _run_act_case(act_tmp_root, "healthy", HEALTHY_CONFIG)
    output = result.stdout + result.stderr

    assert result.returncode == 0, f"act push should succeed for a valid config:\n{output}"
    assert "Job succeeded" in output

    assert "Summary: 0 expired, 0 warning, 2 ok (2 total)" in output
    assert "_None_" in output  # empty Expired/Warning sections render as "_None_"
    assert "WEB_CERT" in output and "| 79 |" in output
    assert "SSH_KEY" in output and "| 119 |" in output

    assert '"expired": []' in output
    assert '"warning": []' in output
    assert '"summary": {' in output
    assert '"total": 2' in output


def test_missing_config_case_fails_the_job_with_a_clear_error(act_tmp_root):
    """No config file at all: nothing to report -- this is the one case that must fail."""
    result = _run_act_case(act_tmp_root, "missing_config", None)
    output = result.stdout + result.stderr

    assert result.returncode != 0, "a missing config file must fail the pipeline, not succeed silently"
    assert "Job failed" in output
    assert "Error: Config file not found: fixtures/secrets-config.json" in output


def test_act_result_file_was_created():
    assert ACT_RESULT_PATH.is_file(), "act-result.txt must exist as a required artifact"
    content = ACT_RESULT_PATH.read_text()
    assert "TEST CASE: mixed" in content
    assert "TEST CASE: healthy" in content
    assert "TEST CASE: missing_config" in content
