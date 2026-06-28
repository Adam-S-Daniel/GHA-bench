"""Unit tests for the secret-rotation validator (red/green TDD).

Each test was written *before* the corresponding implementation. These tests
exercise the pure logic of `secret_rotation_validator` directly and run inside
the GitHub Actions pipeline (the workflow's `unit-tests` job invokes pytest on
this directory), so every case here also executes "through the pipeline".
"""

import datetime

import secret_rotation_validator as srv


# ---------------------------------------------------------------------------
# Step 1: classify a single secret by urgency.
# ---------------------------------------------------------------------------
def test_classify_expired_secret():
    # Rotated 2026-03-01 with a 90-day policy => expires 2026-05-30, which is
    # before "now" (2026-06-28) => EXPIRED.
    secret = {
        "name": "DB_PASSWORD",
        "last_rotated": "2026-03-01",
        "rotation_policy_days": 90,
        "required_by": ["billing-api"],
    }
    now = datetime.date(2026, 6, 28)
    result = srv.classify_secret(secret, now=now, warning_days=14)
    assert result["status"] == "expired"
    assert result["days_until_expiry"] == -29
    assert result["message"] == "29 days overdue"
    assert result["expires_on"] == "2026-05-30"


def test_classify_warning_secret_within_window():
    # Expires in 6 days, warning window is 14 => WARNING.
    secret = {
        "name": "AWS_ACCESS_KEY",
        "last_rotated": "2026-04-05",
        "rotation_policy_days": 90,
        "required_by": ["ingest"],
    }
    now = datetime.date(2026, 6, 28)
    result = srv.classify_secret(secret, now=now, warning_days=14)
    assert result["status"] == "warning"
    assert result["days_until_expiry"] == 6
    assert result["message"] == "expires in 6 days"


def test_classify_ok_secret_outside_window():
    secret = {
        "name": "TLS_CERT",
        "last_rotated": "2026-06-01",
        "rotation_policy_days": 365,
        "required_by": ["edge"],
    }
    now = datetime.date(2026, 6, 28)
    result = srv.classify_secret(secret, now=now, warning_days=14)
    assert result["status"] == "ok"
    assert result["days_until_expiry"] == 338


def test_warning_window_is_configurable():
    # Expires in 22 days: OK at a 14-day window, WARNING at a 30-day window.
    secret = {
        "name": "GH_TOKEN",
        "last_rotated": "2026-04-21",
        "rotation_policy_days": 90,
        "required_by": ["release"],
    }
    now = datetime.date(2026, 6, 28)
    assert srv.classify_secret(secret, now=now, warning_days=14)["status"] == "ok"
    assert srv.classify_secret(secret, now=now, warning_days=30)["status"] == "warning"


def test_expiring_today_is_warning_boundary():
    # days_until_expiry == 0 must fall in the warning bucket, not expired.
    secret = {"name": "X", "last_rotated": "2026-03-30", "rotation_policy_days": 90}
    now = datetime.date(2026, 6, 28)
    assert srv.classify_secret(secret, now=now, warning_days=0)["status"] == "warning"


# ---------------------------------------------------------------------------
# Step 2: build a full report (group by urgency + summary counts).
# ---------------------------------------------------------------------------
def _sample_config():
    return {
        "warning_days": 14,
        "now": "2026-06-28",
        "secrets": [
            {"name": "DB_PASSWORD", "last_rotated": "2026-01-01",
             "rotation_policy_days": 90, "required_by": ["billing-api", "worker"]},
            {"name": "LEGACY_API_TOKEN", "last_rotated": "2025-12-01",
             "rotation_policy_days": 30, "required_by": ["legacy-sync"]},
            {"name": "AWS_ACCESS_KEY", "last_rotated": "2026-04-05",
             "rotation_policy_days": 90, "required_by": ["ingest", "api"]},
            {"name": "TLS_CERT", "last_rotated": "2026-06-01",
             "rotation_policy_days": 365, "required_by": ["edge"]},
        ],
    }


def test_build_report_groups_and_counts():
    report = srv.build_report(_sample_config(), warning_days=14,
                              now=datetime.date(2026, 6, 28))
    assert report["summary"] == {"expired": 2, "warning": 1, "ok": 1, "total": 4}
    # Each group is sorted most-urgent-first (smallest days_until_expiry).
    assert [s["name"] for s in report["groups"]["expired"]] == [
        "LEGACY_API_TOKEN", "DB_PASSWORD"]
    assert [s["name"] for s in report["groups"]["warning"]] == ["AWS_ACCESS_KEY"]
    assert [s["name"] for s in report["groups"]["ok"]] == ["TLS_CERT"]
    assert report["generated_at"] == "2026-06-28"
    assert report["warning_days"] == 14


def test_build_report_sorts_expired_by_most_overdue_first():
    # LEGACY_API_TOKEN is more overdue than DB_PASSWORD, so it should sort first.
    report = srv.build_report(_sample_config(), warning_days=14,
                              now=datetime.date(2026, 6, 28))
    overdue = report["groups"]["expired"]
    assert overdue[0]["name"] == "LEGACY_API_TOKEN"
    assert overdue[0]["days_until_expiry"] < overdue[1]["days_until_expiry"]


# ---------------------------------------------------------------------------
# Step 3: render the report in multiple output formats.
# ---------------------------------------------------------------------------
import json  # noqa: E402  (kept next to the tests that use it)


def _sample_report():
    return srv.build_report(_sample_config(), warning_days=14,
                            now=datetime.date(2026, 6, 28))


def test_render_json_round_trips_to_report():
    text = srv.render(_sample_report(), fmt="json")
    parsed = json.loads(text)
    assert parsed["summary"] == {"expired": 2, "warning": 1, "ok": 1, "total": 4}
    assert parsed["groups"]["warning"][0]["name"] == "AWS_ACCESS_KEY"


def test_render_markdown_has_title_summary_and_grouped_sections():
    text = srv.render(_sample_report(), fmt="markdown")
    assert "# Secret Rotation Report" in text
    assert "Warning window: 14 days" in text
    # Summary table rows (substring tolerant of surrounding pipes/whitespace).
    assert "Expired | 2" in text
    assert "Warning | 1" in text
    assert "OK | 1" in text
    assert "Total | 4" in text
    # Grouped sections, each headed with its count.
    assert "## Expired (2)" in text
    assert "## Warning (1)" in text
    assert "## OK (1)" in text
    # A representative row from the expired group, including the overdue message
    # and the required-by services joined with commas.
    assert "DB_PASSWORD" in text
    assert "88 days overdue" in text
    assert "billing-api, worker" in text


def test_render_markdown_empty_group_shows_none():
    report = srv.build_report(
        {"secrets": [{"name": "OK_ONE", "last_rotated": "2026-06-20",
                      "rotation_policy_days": 365}]},
        warning_days=14, now=datetime.date(2026, 6, 28))
    text = srv.render(report, fmt="markdown")
    assert "## Expired (0)" in text
    assert "_None_" in text


def test_render_summary_is_single_parseable_line():
    text = srv.render(_sample_report(), fmt="summary")
    assert text.strip() == "expired=2 warning=1 ok=1 total=4"


def test_render_rejects_unknown_format():
    import pytest
    with pytest.raises(ValueError):
        srv.render(_sample_report(), fmt="xml")


# ---------------------------------------------------------------------------
# Step 4: load + validate the configuration file (graceful errors).
# ---------------------------------------------------------------------------
import pytest  # noqa: E402


def _write(tmp_path, payload):
    """Write ``payload`` (dict -> JSON, or raw str) to a temp file, return path."""
    path = tmp_path / "secrets.json"
    path.write_text(payload if isinstance(payload, str) else json.dumps(payload))
    return str(path)


def test_load_config_reads_valid_file(tmp_path):
    path = _write(tmp_path, _sample_config())
    config = srv.load_config(path)
    assert len(config["secrets"]) == 4
    assert config["warning_days"] == 14


def test_load_config_missing_file_raises_configerror():
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config("/no/such/file.json")
    assert "not found" in str(exc.value).lower()


def test_load_config_invalid_json_raises_configerror(tmp_path):
    path = _write(tmp_path, "{ this is not json ")
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(path)
    assert "json" in str(exc.value).lower()


def test_load_config_missing_secrets_key_raises(tmp_path):
    path = _write(tmp_path, {"warning_days": 14})
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(path)
    assert "secrets" in str(exc.value).lower()


def test_load_config_secrets_not_a_list_raises(tmp_path):
    path = _write(tmp_path, {"secrets": {"name": "X"}})
    with pytest.raises(srv.ConfigError):
        srv.load_config(path)


def test_load_config_secret_missing_field_names_the_secret(tmp_path):
    path = _write(tmp_path, {"secrets": [
        {"name": "GOOD", "last_rotated": "2026-01-01", "rotation_policy_days": 30},
        {"name": "BAD_ONE", "last_rotated": "2026-01-01"},  # no policy
    ]})
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(path)
    msg = str(exc.value)
    assert "BAD_ONE" in msg and "rotation_policy_days" in msg


def test_load_config_bad_date_raises(tmp_path):
    path = _write(tmp_path, {"secrets": [
        {"name": "BAD_DATE", "last_rotated": "01/01/2026", "rotation_policy_days": 30},
    ]})
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(path)
    assert "BAD_DATE" in str(exc.value)


def test_load_config_non_positive_policy_raises(tmp_path):
    path = _write(tmp_path, {"secrets": [
        {"name": "ZERO", "last_rotated": "2026-01-01", "rotation_policy_days": 0},
    ]})
    with pytest.raises(srv.ConfigError) as exc:
        srv.load_config(path)
    assert "ZERO" in str(exc.value)


# ---------------------------------------------------------------------------
# Step 5: the CLI entry point (main) wires everything together.
# ---------------------------------------------------------------------------
def test_main_prints_json_and_returns_zero(tmp_path, capsys):
    path = _write(tmp_path, _sample_config())
    code = srv.main(["--config", path, "--format", "json"])
    out = capsys.readouterr().out
    assert code == 0
    assert json.loads(out)["summary"]["expired"] == 2


def test_main_uses_config_defaults_for_now_and_window(tmp_path, capsys):
    # _sample_config() carries now=2026-06-28 and warning_days=14.
    path = _write(tmp_path, _sample_config())
    code = srv.main(["--config", path, "--format", "summary"])
    assert code == 0
    assert capsys.readouterr().out.strip() == "expired=2 warning=1 ok=1 total=4"


def test_main_cli_flag_overrides_config_warning_days(tmp_path, capsys):
    # Narrowing the window to 0 moves AWS_ACCESS_KEY (expires in 6) out of warning.
    path = _write(tmp_path, _sample_config())
    code = srv.main(["--config", path, "--format", "summary", "--warning-days", "0"])
    assert code == 0
    assert capsys.readouterr().out.strip() == "expired=2 warning=0 ok=2 total=4"


def test_main_defaults_to_markdown_when_no_format_given(tmp_path, capsys):
    cfg = _sample_config()
    del cfg["now"]  # exercise the today() path without asserting exact counts
    path = _write(tmp_path, cfg)
    code = srv.main(["--config", path])
    assert code == 0
    assert "# Secret Rotation Report" in capsys.readouterr().out


def test_main_missing_file_returns_2_with_stderr_message(capsys):
    code = srv.main(["--config", "/no/such/file.json"])
    assert code == 2
    assert "not found" in capsys.readouterr().err.lower()


def test_main_invalid_now_returns_2(tmp_path, capsys):
    path = _write(tmp_path, {"secrets": [
        {"name": "A", "last_rotated": "2026-01-01", "rotation_policy_days": 30}]})
    code = srv.main(["--config", path, "--now", "not-a-date"])
    assert code == 2
    assert "now" in capsys.readouterr().err.lower()


def test_main_fail_on_expired_returns_3_when_expired_present(tmp_path, capsys):
    path = _write(tmp_path, _sample_config())
    code = srv.main(["--config", path, "--format", "summary", "--fail-on", "expired"])
    assert code == 3


def test_main_fail_on_expired_returns_0_when_clean(tmp_path, capsys):
    path = _write(tmp_path, {"now": "2026-06-28", "secrets": [
        {"name": "FRESH", "last_rotated": "2026-06-20", "rotation_policy_days": 365}]})
    code = srv.main(["--config", path, "--format", "summary", "--fail-on", "expired"])
    assert code == 0
