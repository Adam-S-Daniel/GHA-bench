"""
Red/Green TDD suite for secret_rotation_validator.py.

Tests are grouped by the piece of functionality they drive out, in the
order they were written (date math -> classification -> report building
-> formatters -> config loading/validation -> CLI). Each group starts by
asserting behavior that does not exist yet, then the implementation is
added to make it pass.
"""
import datetime
import json
import subprocess
import sys
from pathlib import Path

import pytest

# The module under test does not exist yet on the very first run of this
# file -- that import failure IS the first red test.
import secret_rotation_validator as srv

FIXTURES = Path(__file__).parent.parent / "fixtures"


# ---------------------------------------------------------------------------
# Date math
# ---------------------------------------------------------------------------

def test_parse_date_accepts_iso_format():
    assert srv.parse_date("2026-06-05") == datetime.date(2026, 6, 5)


def test_parse_date_rejects_malformed_string():
    with pytest.raises(srv.SecretRotationError) as exc_info:
        srv.parse_date("not-a-date")
    assert "not-a-date" in str(exc_info.value)


def test_days_since_rotation_counts_full_days():
    today = datetime.date(2026, 7, 1)
    last_rotated = datetime.date(2026, 6, 29)
    assert srv.days_since(last_rotated, today) == 2


def test_days_until_expiry_is_rotation_days_minus_days_since():
    today = datetime.date(2026, 7, 1)
    secret = {"name": "x", "last_rotated": "2026-06-05", "rotation_days": 30}
    # 26 days have elapsed since 2026-06-05, policy allows 30 -> 4 remain.
    assert srv.days_until_expiry(secret, today) == 4


# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

def test_classify_expired_when_past_rotation_window():
    today = datetime.date(2026, 7, 1)
    secret = {"name": "prod-db-password", "last_rotated": "2026-01-01", "rotation_days": 90}
    assert srv.classify(secret, today, warning_days=7) == "expired"


def test_classify_warning_when_within_warning_window():
    today = datetime.date(2026, 7, 1)
    secret = {"name": "stripe-api-key", "last_rotated": "2026-06-05", "rotation_days": 30}
    assert srv.classify(secret, today, warning_days=7) == "warning"


def test_classify_ok_when_far_from_expiry():
    today = datetime.date(2026, 7, 1)
    secret = {"name": "internal-jwt-signing-key", "last_rotated": "2026-06-29", "rotation_days": 60}
    assert srv.classify(secret, today, warning_days=7) == "ok"


def test_classify_expired_on_exact_boundary_day():
    # Exactly rotation_days elapsed -> zero days remain -> already expired,
    # not "warning" (rotation is due today, not merely upcoming).
    today = datetime.date(2026, 7, 1)
    secret = {"name": "edge-case", "last_rotated": "2026-06-01", "rotation_days": 30}
    assert srv.classify(secret, today, warning_days=7) == "expired"


# ---------------------------------------------------------------------------
# Config loading / validation
# ---------------------------------------------------------------------------

def test_load_config_reads_secrets_and_warning_days():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    assert config["warning_days"] == 7
    assert len(config["secrets"]) == 3
    assert config["secrets"][0]["name"] == "prod-db-password"


def test_load_config_missing_file_raises_meaningful_error():
    with pytest.raises(srv.SecretRotationError) as exc_info:
        srv.load_config(FIXTURES / "does_not_exist.json")
    assert "does_not_exist.json" in str(exc_info.value)


def test_load_config_rejects_bad_date_with_secret_name_in_error():
    with pytest.raises(srv.SecretRotationError) as exc_info:
        srv.load_config(FIXTURES / "invalid_secrets_config.json")
    assert "bad-date-secret" in str(exc_info.value)


# ---------------------------------------------------------------------------
# Report building
# ---------------------------------------------------------------------------

def test_build_report_groups_secrets_by_urgency():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    today = datetime.date(2026, 7, 1)
    report = srv.build_report(config["secrets"], today, config["warning_days"])

    expired_names = [s["name"] for s in report["expired"]]
    warning_names = [s["name"] for s in report["warning"]]
    ok_names = [s["name"] for s in report["ok"]]

    assert expired_names == ["prod-db-password"]
    assert warning_names == ["stripe-api-key"]
    assert ok_names == ["internal-jwt-signing-key"]


def test_build_report_annotates_days_until_expiry():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    today = datetime.date(2026, 7, 1)
    report = srv.build_report(config["secrets"], today, config["warning_days"])
    assert report["warning"][0]["days_until_expiry"] == 4
    assert report["expired"][0]["days_until_expiry"] == -91


def test_build_report_includes_summary_counts():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    today = datetime.date(2026, 7, 1)
    report = srv.build_report(config["secrets"], today, config["warning_days"])
    assert report["summary"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}


# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

def test_render_json_round_trips_summary():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    today = datetime.date(2026, 7, 1)
    report = srv.build_report(config["secrets"], today, config["warning_days"])
    rendered = srv.render_json(report)
    parsed = json.loads(rendered)
    assert parsed["summary"]["expired"] == 1
    assert parsed["expired"][0]["name"] == "prod-db-password"


def test_render_markdown_contains_urgency_sections_and_table_rows():
    config = srv.load_config(FIXTURES / "secrets_config.json")
    today = datetime.date(2026, 7, 1)
    report = srv.build_report(config["secrets"], today, config["warning_days"])
    md = srv.render_markdown(report)

    assert "## Expired" in md
    assert "## Warning" in md
    assert "## OK" in md
    assert "| prod-db-password |" in md
    assert "billing-service, reporting-service" in md


def test_render_markdown_omits_empty_sections():
    today = datetime.date(2026, 7, 1)
    all_ok_secrets = [
        {"name": "solo", "last_rotated": "2026-06-29", "rotation_days": 60, "required_by": ["svc"]}
    ]
    report = srv.build_report(all_ok_secrets, today, warning_days=7)
    md = srv.render_markdown(report)
    assert "## OK" in md
    assert "## Expired" not in md
    assert "## Warning" not in md


# ---------------------------------------------------------------------------
# CLI (invoked as a subprocess, exercising main() end-to-end)
# ---------------------------------------------------------------------------

def test_cli_json_output_exits_zero_and_prints_summary(tmp_path):
    module_path = Path(__file__).parent.parent / "secret_rotation_validator.py"
    result = subprocess.run(
        [
            sys.executable, str(module_path),
            "--config", str(FIXTURES / "secrets_config.json"),
            "--format", "json",
            "--today", "2026-07-01",
        ],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    payload = json.loads(result.stdout)
    assert payload["summary"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}


def test_cli_markdown_output_exits_zero(tmp_path):
    module_path = Path(__file__).parent.parent / "secret_rotation_validator.py"
    result = subprocess.run(
        [
            sys.executable, str(module_path),
            "--config", str(FIXTURES / "secrets_config.json"),
            "--format", "markdown",
            "--today", "2026-07-01",
        ],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "## Expired" in result.stdout


def test_cli_nonzero_exit_with_expired_secrets_flag(tmp_path):
    # --fail-on-expired turns "there is at least one expired secret" into a
    # non-zero exit code, so CI can fail the job on the condition.
    module_path = Path(__file__).parent.parent / "secret_rotation_validator.py"
    result = subprocess.run(
        [
            sys.executable, str(module_path),
            "--config", str(FIXTURES / "secrets_config.json"),
            "--format", "json",
            "--today", "2026-07-01",
            "--fail-on-expired",
        ],
        capture_output=True, text=True,
    )
    assert result.returncode == 1


def test_cli_missing_config_file_prints_error_and_exits_nonzero(tmp_path):
    module_path = Path(__file__).parent.parent / "secret_rotation_validator.py"
    result = subprocess.run(
        [
            sys.executable, str(module_path),
            "--config", str(FIXTURES / "does_not_exist.json"),
            "--format", "json",
        ],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "does_not_exist.json" in result.stderr
