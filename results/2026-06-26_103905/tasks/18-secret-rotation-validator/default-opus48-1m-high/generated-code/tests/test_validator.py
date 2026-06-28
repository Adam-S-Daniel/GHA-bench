"""Unit tests for the secret rotation validator (red/green TDD).

These tests drive the design of `secret_rotation_validator.py`. Each was
written *before* the corresponding implementation. We use a fixed reference
date (`NOW`) everywhere so the suite is deterministic and never depends on the
real wall clock.
"""
import json
from datetime import date

import pytest

import secret_rotation_validator as srv

# A fixed "today" used across the whole suite so results are reproducible.
NOW = date(2026, 6, 27)


# ---------------------------------------------------------------------------
# Cycle 1: classify a single secret into expired / warning / ok
# ---------------------------------------------------------------------------
def test_classify_expired_secret():
    secret = {
        "name": "DB_PASSWORD",
        "last_rotated": "2026-01-01",
        "rotation_policy_days": 90,  # expires 2026-04-01 -> already past NOW
        "required_by": ["billing-api"],
    }
    result = srv.classify_secret(secret, now=NOW, warning_days=14)
    assert result["status"] == "expired"
    assert result["expiry_date"] == date(2026, 4, 1)
    # Negative days-until-expiry means it lapsed in the past.
    assert result["days_until_expiry"] == (date(2026, 4, 1) - NOW).days


def test_classify_warning_secret():
    # Expires 2026-07-01, i.e. 4 days after NOW -> within the 14-day window.
    secret = {
        "name": "API_TOKEN",
        "last_rotated": "2026-06-01",
        "rotation_policy_days": 30,
        "required_by": ["web", "worker"],
    }
    result = srv.classify_secret(secret, now=NOW, warning_days=14)
    assert result["status"] == "warning"
    assert result["days_until_expiry"] == 4


def test_classify_ok_secret():
    # Expires 2027-06-20, far outside the warning window.
    secret = {
        "name": "TLS_CERT",
        "last_rotated": "2026-06-20",
        "rotation_policy_days": 365,
        "required_by": ["gateway"],
    }
    result = srv.classify_secret(secret, now=NOW, warning_days=14)
    assert result["status"] == "ok"


def test_warning_window_is_inclusive_boundary():
    # Exactly `warning_days` away counts as a warning, not ok.
    secret = {
        "name": "EDGE",
        "last_rotated": "2026-06-13",
        "rotation_policy_days": 14,  # expiry 2026-06-27 == NOW -> 0 days left
        "required_by": [],
    }
    on_deadline = srv.classify_secret(secret, now=NOW, warning_days=14)
    assert on_deadline["days_until_expiry"] == 0
    assert on_deadline["status"] == "warning"


# ---------------------------------------------------------------------------
# Cycle 2: build a full report grouped by urgency
# ---------------------------------------------------------------------------
def test_build_report_groups_by_urgency():
    config = {
        "secrets": [
            {"name": "DB_PASSWORD", "last_rotated": "2026-01-01",
             "rotation_policy_days": 90, "required_by": ["billing"]},
            {"name": "API_TOKEN", "last_rotated": "2026-06-01",
             "rotation_policy_days": 30, "required_by": ["web"]},
            {"name": "TLS_CERT", "last_rotated": "2026-06-20",
             "rotation_policy_days": 365, "required_by": ["gateway"]},
        ]
    }
    report = srv.build_report(config, now=NOW, warning_days=14)

    assert report["generated_for"] == "2026-06-27"
    assert report["warning_days"] == 14
    assert report["counts"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}
    # Grouped lists carry the classified secrets.
    assert [s["name"] for s in report["groups"]["expired"]] == ["DB_PASSWORD"]
    assert [s["name"] for s in report["groups"]["warning"]] == ["API_TOKEN"]
    assert [s["name"] for s in report["groups"]["ok"]] == ["TLS_CERT"]


def test_build_report_sorts_within_group_by_urgency():
    # Two expired secrets: the more overdue one should come first.
    config = {
        "secrets": [
            {"name": "LESS_OVERDUE", "last_rotated": "2026-05-01",
             "rotation_policy_days": 30, "required_by": []},   # expired 2026-05-31
            {"name": "MORE_OVERDUE", "last_rotated": "2026-01-01",
             "rotation_policy_days": 30, "required_by": []},   # expired 2026-01-31
        ]
    }
    report = srv.build_report(config, now=NOW, warning_days=14)
    assert [s["name"] for s in report["groups"]["expired"]] == [
        "MORE_OVERDUE", "LESS_OVERDUE",
    ]


# ---------------------------------------------------------------------------
# Cycle 3: rendering — summary, JSON, markdown
# ---------------------------------------------------------------------------
MIXED_CONFIG = {
    "secrets": [
        {"name": "DB_PASSWORD", "last_rotated": "2026-01-01",
         "rotation_policy_days": 90, "required_by": ["billing"]},
        {"name": "API_TOKEN", "last_rotated": "2026-06-01",
         "rotation_policy_days": 30, "required_by": ["web", "worker"]},
        {"name": "TLS_CERT", "last_rotated": "2026-06-20",
         "rotation_policy_days": 365, "required_by": ["gateway"]},
    ]
}


def test_render_summary_is_machine_parseable():
    report = srv.build_report(MIXED_CONFIG, now=NOW, warning_days=14)
    line = srv.render_summary(report)
    assert line == "ROTATION_SUMMARY expired=1 warning=1 ok=1 total=3"


def test_render_json_round_trips_and_keeps_iso_dates():
    report = srv.build_report(MIXED_CONFIG, now=NOW, warning_days=14)
    payload = json.loads(srv.render_json(report))
    assert payload["counts"] == {"expired": 1, "warning": 1, "ok": 1, "total": 3}
    # Dates must serialise as ISO strings, not Python date reprs.
    assert payload["groups"]["expired"][0]["expiry_date"] == "2026-04-01"
    assert payload["groups"]["warning"][0]["name"] == "API_TOKEN"


def test_render_markdown_has_table_and_grouped_sections():
    report = srv.build_report(MIXED_CONFIG, now=NOW, warning_days=14)
    md = srv.render_markdown(report)
    # Title carries the reference date.
    assert "# Secret Rotation Report (as of 2026-06-27)" in md
    # A counts line for a quick scan.
    assert "Expired: 1 | Warning: 1 | OK: 1 | Total: 3" in md
    # Section headers per urgency.
    assert "## Expired (1)" in md
    assert "## Warning (1)" in md
    assert "## OK (1)" in md
    # Markdown table header + a data row with the secret + its services.
    assert "| Secret | Last Rotated | Policy (days) | Expiry | Days Left | Required By |" in md
    assert "| DB_PASSWORD |" in md
    assert "web, worker" in md  # required_by joined


def test_render_markdown_handles_empty_group():
    report = srv.build_report({"secrets": []}, now=NOW, warning_days=14)
    md = srv.render_markdown(report)
    assert "## Expired (0)" in md
    assert "_None_" in md  # empty groups get a placeholder, not a broken table


# ---------------------------------------------------------------------------
# Cycle 4: config loading + error handling
# ---------------------------------------------------------------------------
def test_load_config_reads_json(tmp_path):
    p = tmp_path / "c.json"
    p.write_text(json.dumps(MIXED_CONFIG))
    cfg = srv.load_config(str(p))
    assert len(cfg["secrets"]) == 3


def test_load_config_missing_file_raises_clear_error(tmp_path):
    missing = tmp_path / "nope.json"
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(str(missing))
    assert "not found" in str(exc.value).lower()


def test_load_config_invalid_json_raises_clear_error(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{ this is not json }")
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(str(p))
    assert "invalid json" in str(exc.value).lower()


# ---------------------------------------------------------------------------
# Cycle 5: the CLI entrypoint (main)
# ---------------------------------------------------------------------------
def _write_mixed(tmp_path):
    p = tmp_path / "config.json"
    p.write_text(json.dumps(MIXED_CONFIG))
    return str(p)


def test_main_summary_format(tmp_path, capsys):
    rc = srv.main([
        "--config", _write_mixed(tmp_path),
        "--now", "2026-06-27", "--warning-days", "14", "--format", "summary",
    ])
    out = capsys.readouterr().out
    assert rc == 0
    assert "ROTATION_SUMMARY expired=1 warning=1 ok=1 total=3" in out


def test_main_json_format(tmp_path, capsys):
    rc = srv.main([
        "--config", _write_mixed(tmp_path),
        "--now", "2026-06-27", "--format", "json",
    ])
    out = capsys.readouterr().out
    assert rc == 0
    payload = json.loads(out)
    assert payload["counts"]["total"] == 3


def test_main_markdown_is_default_format(tmp_path, capsys):
    rc = srv.main(["--config", _write_mixed(tmp_path), "--now", "2026-06-27"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "# Secret Rotation Report (as of 2026-06-27)" in out


def test_main_missing_file_returns_error_code(tmp_path, capsys):
    rc = srv.main(["--config", str(tmp_path / "missing.json"), "--now", "2026-06-27"])
    err = capsys.readouterr().err
    assert rc == 2
    assert "Error:" in err


def test_main_fail_on_expired_sets_nonzero_exit(tmp_path, capsys):
    # --fail-on expired makes the process exit non-zero when expired secrets exist,
    # so a scheduled CI job can surface the problem. Default behaviour never fails.
    rc = srv.main([
        "--config", _write_mixed(tmp_path), "--now", "2026-06-27",
        "--format", "summary", "--fail-on", "expired",
    ])
    assert rc == 1


def test_main_default_never_fails_even_with_expired(tmp_path):
    rc = srv.main([
        "--config", _write_mixed(tmp_path), "--now", "2026-06-27",
        "--format", "summary",
    ])
    assert rc == 0
