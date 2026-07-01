"""
TDD test suite for the secret rotation validator.

Approach: red/green/refactor. Each test is written before the corresponding
functionality exists in secret_rotation_validator.py, then the minimum code
is added to make it pass.

Fixtures use a fixed "today" date so results are deterministic regardless of
when the suite runs.
"""
import datetime
import json
import subprocess
import sys

import pytest

from secret_rotation_validator import (
    SecretConfigError,
    build_report,
    check_secret_status,
    load_secrets,
    render_json,
    render_markdown,
)

FIXED_TODAY = datetime.date(2026, 7, 1)


# ---------------------------------------------------------------------------
# check_secret_status: the core status classification logic
# ---------------------------------------------------------------------------

def test_secret_status_is_ok_when_far_from_expiry():
    secret = {
        "name": "db-password",
        "last_rotated": "2026-06-25",
        "rotation_days": 90,
        "required_by": ["api-service"],
    }
    result = check_secret_status(secret, today=FIXED_TODAY, warning_days=7)
    assert result["status"] == "ok"
    assert result["days_until_expiry"] == 84


def test_secret_status_is_warning_within_window():
    secret = {
        "name": "api-key",
        "last_rotated": "2026-04-05",
        "rotation_days": 90,
        "required_by": ["billing-service"],
    }
    result = check_secret_status(secret, today=FIXED_TODAY, warning_days=7)
    assert result["status"] == "warning"
    assert result["days_until_expiry"] == 3


def test_secret_status_is_expired_when_past_rotation_days():
    secret = {
        "name": "tls-cert",
        "last_rotated": "2026-01-01",
        "rotation_days": 30,
        "required_by": ["edge-proxy"],
    }
    result = check_secret_status(secret, today=FIXED_TODAY, warning_days=7)
    assert result["status"] == "expired"
    assert result["days_until_expiry"] < 0


# ---------------------------------------------------------------------------
# load_secrets: reading and validating the mock config file
# ---------------------------------------------------------------------------

def test_load_secrets_reads_valid_config(tmp_path):
    config_path = tmp_path / "secrets.json"
    config_path.write_text(json.dumps({
        "secrets": [
            {
                "name": "db-password",
                "last_rotated": "2026-06-01",
                "rotation_days": 90,
                "required_by": ["api-service"],
            }
        ]
    }))
    secrets = load_secrets(str(config_path))
    assert len(secrets) == 1
    assert secrets[0]["name"] == "db-password"


def test_load_secrets_raises_on_missing_required_field(tmp_path):
    config_path = tmp_path / "bad_secrets.json"
    config_path.write_text(json.dumps({
        "secrets": [{"name": "missing-fields", "last_rotated": "2026-01-01"}]
    }))
    with pytest.raises(SecretConfigError, match="rotation_days"):
        load_secrets(str(config_path))


def test_load_secrets_raises_on_malformed_top_level(tmp_path):
    config_path = tmp_path / "malformed.json"
    config_path.write_text(json.dumps({"not_secrets": []}))
    with pytest.raises(SecretConfigError, match="secrets"):
        load_secrets(str(config_path))


def test_load_secrets_raises_meaningful_error_on_missing_file(tmp_path):
    missing_path = tmp_path / "does_not_exist.json"
    with pytest.raises(SecretConfigError, match="does_not_exist.json"):
        load_secrets(str(missing_path))


# ---------------------------------------------------------------------------
# build_report: grouping secrets by urgency
# ---------------------------------------------------------------------------

SAMPLE_SECRETS = [
    {
        "name": "tls-cert",
        "last_rotated": "2026-01-01",
        "rotation_days": 30,
        "required_by": ["edge-proxy"],
    },
    {
        "name": "api-key",
        "last_rotated": "2026-04-05",
        "rotation_days": 90,
        "required_by": ["billing-service"],
    },
    {
        "name": "db-password",
        "last_rotated": "2026-06-25",
        "rotation_days": 90,
        "required_by": ["api-service"],
    },
]


def test_build_report_groups_secrets_by_status():
    report = build_report(SAMPLE_SECRETS, today=FIXED_TODAY, warning_days=7)
    assert [s["name"] for s in report["expired"]] == ["tls-cert"]
    assert [s["name"] for s in report["warning"]] == ["api-key"]
    assert [s["name"] for s in report["ok"]] == ["db-password"]


def test_build_report_includes_summary_counts():
    report = build_report(SAMPLE_SECRETS, today=FIXED_TODAY, warning_days=7)
    assert report["summary"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}


# ---------------------------------------------------------------------------
# render_json / render_markdown: output formats
# ---------------------------------------------------------------------------

def test_render_json_round_trips_report():
    report = build_report(SAMPLE_SECRETS, today=FIXED_TODAY, warning_days=7)
    output = render_json(report)
    parsed = json.loads(output)
    assert parsed["summary"]["expired"] == 1
    assert parsed["expired"][0]["name"] == "tls-cert"


def test_render_markdown_contains_table_and_sections():
    report = build_report(SAMPLE_SECRETS, today=FIXED_TODAY, warning_days=7)
    output = render_markdown(report)
    assert "# Secret Rotation Report" in output
    assert "## Expired" in output
    assert "## Warning" in output
    assert "## OK" in output
    assert "tls-cert" in output
    assert "| Name | Status | Days Until Expiry | Expiry Date | Required By |" in output


# ---------------------------------------------------------------------------
# CLI: end-to-end behavior via the command line entry point
# ---------------------------------------------------------------------------

def _write_fixture(tmp_path, secrets):
    config_path = tmp_path / "secrets.json"
    config_path.write_text(json.dumps({"secrets": secrets}))
    return config_path


def test_cli_json_output_and_fail_on_expired_exit_code(tmp_path):
    config_path = _write_fixture(tmp_path, SAMPLE_SECRETS)
    result = subprocess.run(
        [sys.executable, "secret_rotation_validator.py", str(config_path),
         "--format", "json", "--fail-on-expired"],
        capture_output=True, text=True,
    )
    assert result.returncode == 1
    parsed = json.loads(result.stdout)
    assert parsed["summary"]["expired"] == 1


def test_cli_succeeds_without_fail_on_expired_flag(tmp_path):
    config_path = _write_fixture(tmp_path, SAMPLE_SECRETS)
    result = subprocess.run(
        [sys.executable, "secret_rotation_validator.py", str(config_path)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "# Secret Rotation Report" in result.stdout


def test_cli_reports_error_for_missing_config(tmp_path):
    missing_path = tmp_path / "nope.json"
    result = subprocess.run(
        [sys.executable, "secret_rotation_validator.py", str(missing_path)],
        capture_output=True, text=True,
    )
    assert result.returncode == 2
    assert "Error" in result.stderr
