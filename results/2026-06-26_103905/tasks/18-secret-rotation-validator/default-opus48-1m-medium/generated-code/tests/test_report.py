"""Red/green TDD — unit 2: report building, rendering, errors, and CLI."""
import datetime
import json
import os
import subprocess
import sys

import pytest

from secret_rotation_validator import (
    ValidationError,
    build_report,
    classify_secret,
    load_config,
    main,
    render_json,
    render_markdown,
)

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(HERE, "fixtures", "secrets.json")
NOW = datetime.date(2026, 6, 27)


def _report():
    config = load_config(FIXTURE)
    return build_report(config, now=NOW, warning_days=14)


# --- grouping & summary ----------------------------------------------------
def test_build_report_groups_by_urgency():
    report = _report()
    assert report["summary"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}
    assert [s["name"] for s in report["secrets"]["expired"]] == ["DB_PASSWORD"]
    assert [s["name"] for s in report["secrets"]["warning"]] == ["API_KEY"]
    assert [s["name"] for s in report["secrets"]["ok"]] == ["TLS_CERT"]
    assert report["generated_at"] == "2026-06-27"
    assert report["warning_days"] == 14


def test_groups_sorted_soonest_due_first():
    config = {
        "secrets": [
            {"name": "A", "last_rotated": "2026-01-01", "rotation_policy_days": 30},
            {"name": "B", "last_rotated": "2026-01-01", "rotation_policy_days": 10},
        ]
    }
    report = build_report(config, now=NOW, warning_days=0)
    # Both expired; B (due earlier) has the more negative days_until -> first.
    assert [s["name"] for s in report["secrets"]["expired"]] == ["B", "A"]


# --- rendering -------------------------------------------------------------
def test_render_json_roundtrips():
    report = _report()
    parsed = json.loads(render_json(report))
    assert parsed["summary"]["expired"] == 1
    assert parsed["secrets"]["warning"][0]["name"] == "API_KEY"


def test_render_markdown_has_sections_and_rows():
    md = render_markdown(_report())
    assert "# Secret Rotation Report" in md
    assert "Summary: 1 expired, 1 warning, 1 ok (3 total)" in md
    assert "## EXPIRED (1)" in md
    assert "## WARNING (1)" in md
    assert "## OK (1)" in md
    # the expired secret row is present with its computed next-rotation date
    assert "| DB_PASSWORD | 2026-01-01 | 90 | 2026-04-01 | -87 | api, worker |" in md


def test_render_markdown_empty_group_shows_none():
    config = {"secrets": [{"name": "X", "last_rotated": "2026-06-01",
                           "rotation_policy_days": 90}]}
    md = render_markdown(build_report(config, now=NOW, warning_days=14))
    assert "## EXPIRED (0)" in md
    assert "_None_" in md


# --- error handling --------------------------------------------------------
def test_missing_field_raises():
    with pytest.raises(ValidationError, match="missing required field"):
        classify_secret({"name": "X", "last_rotated": "2026-01-01"},
                        now=NOW, warning_days=14)


def test_bad_date_raises():
    with pytest.raises(ValidationError, match="invalid date"):
        classify_secret(
            {"name": "X", "last_rotated": "not-a-date", "rotation_policy_days": 30},
            now=NOW, warning_days=14)


def test_non_positive_policy_raises():
    with pytest.raises(ValidationError, match="invalid rotation_policy_days"):
        classify_secret(
            {"name": "X", "last_rotated": "2026-01-01", "rotation_policy_days": 0},
            now=NOW, warning_days=14)


def test_missing_secrets_key_raises():
    with pytest.raises(ValidationError, match="top-level 'secrets'"):
        build_report({"nope": []}, now=NOW, warning_days=14)


def test_load_config_missing_file_raises():
    with pytest.raises(ValidationError, match="not found"):
        load_config("/no/such/file.json")


def test_load_config_bad_json_raises(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not json")
    with pytest.raises(ValidationError, match="not valid JSON"):
        load_config(str(p))


# --- CLI end-to-end (in-process) ------------------------------------------
def test_main_json_format(capsys):
    rc = main(["--config", FIXTURE, "--now", "2026-06-27", "--format", "json"])
    out = capsys.readouterr().out
    assert rc == 0
    assert json.loads(out)["summary"]["total"] == 3


def test_main_fail_on_expired_returns_2(capsys):
    rc = main(["--config", FIXTURE, "--now", "2026-06-27", "--fail-on-expired"])
    assert rc == 2


def test_main_bad_config_returns_1(capsys):
    rc = main(["--config", "/no/such.json"])
    err = capsys.readouterr().err
    assert rc == 1
    assert "ERROR" in err


# --- CLI as a real subprocess (matches how the workflow invokes it) -------
def test_cli_subprocess_markdown():
    proc = subprocess.run(
        [sys.executable, os.path.join(HERE, "secret_rotation_validator.py"),
         "--config", FIXTURE, "--now", "2026-06-27", "--format", "markdown"],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0
    assert "Summary: 1 expired, 1 warning, 1 ok (3 total)" in proc.stdout
