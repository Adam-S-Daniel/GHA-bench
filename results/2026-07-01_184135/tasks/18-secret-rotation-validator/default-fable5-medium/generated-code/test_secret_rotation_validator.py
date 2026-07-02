"""Tests for the secret rotation validator.

Built with red/green TDD: each test (or group of tests) was written first,
watched to fail, then the minimum implementation was added to make it pass.
"""
import datetime
import json
import tempfile
import unittest
from pathlib import Path

from secret_rotation_validator import (
    ConfigError,
    classify_secret,
    format_json,
    format_markdown,
    generate_report,
    load_config,
)

# Shared fixture: one secret in each urgency bucket as of 2026-07-01.
FIXTURE_SECRETS = [
    {  # expired 10 days ago (2026-03-23 + 90d = 2026-06-21)
        "name": "db-password",
        "last_rotated": "2026-03-23",
        "rotation_days": 90,
        "required_by": ["billing-api", "reporting"],
    },
    {  # warning: expires in 7 days (2026-04-09 + 90d = 2026-07-08)
        "name": "api-token",
        "last_rotated": "2026-04-09",
        "rotation_days": 90,
        "required_by": ["gateway"],
    },
    {  # ok: expires in 168 days
        "name": "tls-cert-key",
        "last_rotated": "2026-06-16",
        "rotation_days": 183,
        "required_by": ["web-frontend"],
    },
]


class TestClassifySecret(unittest.TestCase):
    """TDD cycle 1: classify a single secret as expired / warning / ok."""

    def setUp(self):
        self.today = datetime.date(2026, 7, 1)

    def _secret(self, last_rotated, rotation_days):
        return {
            "name": "db-password",
            "last_rotated": last_rotated,
            "rotation_days": rotation_days,
            "required_by": ["billing-api"],
        }

    def test_expired_secret(self):
        # Rotated 100 days ago with a 90-day policy -> expired 10 days ago.
        result = classify_secret(self._secret("2026-03-23", 90), self.today, warn_days=14)
        self.assertEqual(result["status"], "expired")
        self.assertEqual(result["days_until_expiry"], -10)

    def test_expires_today_is_expired(self):
        # Boundary: expiry date reached today counts as expired.
        result = classify_secret(self._secret("2026-04-02", 90), self.today, warn_days=14)
        self.assertEqual(result["status"], "expired")
        self.assertEqual(result["days_until_expiry"], 0)

    def test_warning_secret(self):
        # Expires in 7 days, inside the 14-day warning window.
        result = classify_secret(self._secret("2026-04-09", 90), self.today, warn_days=14)
        self.assertEqual(result["status"], "warning")
        self.assertEqual(result["days_until_expiry"], 7)

    def test_warning_boundary_is_warning(self):
        # Boundary: expires exactly warn_days from now -> still a warning.
        result = classify_secret(self._secret("2026-04-16", 90), self.today, warn_days=14)
        self.assertEqual(result["status"], "warning")
        self.assertEqual(result["days_until_expiry"], 14)

    def test_ok_secret(self):
        # Expires in 15 days, just outside the 14-day window.
        result = classify_secret(self._secret("2026-04-17", 90), self.today, warn_days=14)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["days_until_expiry"], 15)


class TestLoadConfig(unittest.TestCase):
    """TDD cycle 2: load and validate the JSON config with clear errors."""

    def _write(self, content):
        f = tempfile.NamedTemporaryFile(
            "w", suffix=".json", delete=False, dir=tempfile.gettempdir()
        )
        self.addCleanup(Path(f.name).unlink)
        f.write(content)
        f.close()
        return f.name

    def _valid_config(self):
        return {
            "warn_days": 14,
            "reference_date": "2026-07-01",
            "secrets": [
                {
                    "name": "db-password",
                    "last_rotated": "2026-03-23",
                    "rotation_days": 90,
                    "required_by": ["billing-api"],
                }
            ],
        }

    def test_loads_valid_config(self):
        path = self._write(json.dumps(self._valid_config()))
        config = load_config(path)
        self.assertEqual(config["warn_days"], 14)
        self.assertEqual(config["secrets"][0]["name"], "db-password")

    def test_missing_file_raises_config_error(self):
        with self.assertRaisesRegex(ConfigError, "not found"):
            load_config("/nonexistent/secrets.json")

    def test_invalid_json_raises_config_error(self):
        path = self._write("{not json")
        with self.assertRaisesRegex(ConfigError, "Invalid JSON"):
            load_config(path)

    def test_missing_secret_field_raises_config_error(self):
        config = self._valid_config()
        del config["secrets"][0]["rotation_days"]
        path = self._write(json.dumps(config))
        with self.assertRaisesRegex(ConfigError, "rotation_days"):
            load_config(path)

    def test_bad_date_raises_config_error(self):
        config = self._valid_config()
        config["secrets"][0]["last_rotated"] = "not-a-date"
        path = self._write(json.dumps(config))
        with self.assertRaisesRegex(ConfigError, "last_rotated"):
            load_config(path)

    def test_nonpositive_rotation_days_raises_config_error(self):
        config = self._valid_config()
        config["secrets"][0]["rotation_days"] = 0
        path = self._write(json.dumps(config))
        with self.assertRaisesRegex(ConfigError, "positive integer"):
            load_config(path)

    def test_secrets_must_be_a_list(self):
        path = self._write(json.dumps({"secrets": {}}))
        with self.assertRaisesRegex(ConfigError, "'secrets' must be a list"):
            load_config(path)


class TestGenerateReport(unittest.TestCase):
    """TDD cycle 3: group classified secrets by urgency into a report."""

    def setUp(self):
        self.report = generate_report(
            FIXTURE_SECRETS, today=datetime.date(2026, 7, 1), warn_days=14
        )

    def test_groups_by_urgency(self):
        self.assertEqual(
            [s["name"] for s in self.report["expired"]], ["db-password"]
        )
        self.assertEqual([s["name"] for s in self.report["warning"]], ["api-token"])
        self.assertEqual([s["name"] for s in self.report["ok"]], ["tls-cert-key"])

    def test_summary_counts(self):
        self.assertEqual(
            self.report["summary"],
            {"expired": 1, "warning": 1, "ok": 1, "total": 3},
        )

    def test_metadata_recorded(self):
        self.assertEqual(self.report["reference_date"], "2026-07-01")
        self.assertEqual(self.report["warn_days"], 14)

    def test_most_urgent_first_within_group(self):
        # Two expired secrets: the one expired longest ago sorts first.
        secrets = [
            {"name": "a", "last_rotated": "2026-06-01", "rotation_days": 20,
             "required_by": []},  # expired 10 days ago
            {"name": "b", "last_rotated": "2026-05-01", "rotation_days": 20,
             "required_by": []},  # expired 41 days ago
        ]
        report = generate_report(secrets, datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual([s["name"] for s in report["expired"]], ["b", "a"])


class TestOutputFormats(unittest.TestCase):
    """TDD cycle 4: render the report as a markdown table and as JSON."""

    def setUp(self):
        self.report = generate_report(
            FIXTURE_SECRETS, today=datetime.date(2026, 7, 1), warn_days=14
        )

    def test_markdown_has_table_and_rows(self):
        md = format_markdown(self.report)
        self.assertIn("# Secret Rotation Report", md)
        self.assertIn(
            "| Status | Secret | Expiry date | Days left | Required by |", md
        )
        self.assertIn(
            "| EXPIRED | db-password | 2026-06-21 | -10 | billing-api, reporting |",
            md,
        )
        self.assertIn("| WARNING | api-token | 2026-07-08 | 7 | gateway |", md)
        self.assertIn("| OK | tls-cert-key | 2026-12-16 | 168 | web-frontend |", md)

    def test_markdown_summary_line(self):
        md = format_markdown(self.report)
        self.assertIn("**1 expired**, **1 expiring soon**, 1 ok (3 total)", md)

    def test_json_round_trips(self):
        parsed = json.loads(format_json(self.report))
        self.assertEqual(parsed["summary"]["expired"], 1)
        self.assertEqual(parsed["expired"][0]["name"], "db-password")
        self.assertEqual(parsed["expired"][0]["days_until_expiry"], -10)


class TestCli(unittest.TestCase):
    """TDD cycle 5: CLI wiring — exit codes, format flag, error reporting."""

    def setUp(self):
        import contextlib
        import io

        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        self._redirect = contextlib.ExitStack()
        self._redirect.enter_context(contextlib.redirect_stdout(self.stdout))
        self._redirect.enter_context(contextlib.redirect_stderr(self.stderr))
        self.addCleanup(self._redirect.close)

        config = {
            "warn_days": 14,
            "reference_date": "2026-07-01",
            "secrets": FIXTURE_SECRETS,
        }
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        self.addCleanup(Path(f.name).unlink)
        json.dump(config, f)
        f.close()
        self.config_path = f.name

    def _main(self, *argv):
        from secret_rotation_validator import main

        return main(list(argv))

    def test_json_format_and_exit_zero(self):
        code = self._main("--config", self.config_path, "--format", "json")
        self.assertEqual(code, 0)
        parsed = json.loads(self.stdout.getvalue())
        self.assertEqual(parsed["summary"]["expired"], 1)

    def test_markdown_is_default_format(self):
        self._main("--config", self.config_path)
        self.assertIn("# Secret Rotation Report", self.stdout.getvalue())

    def test_fail_on_expired_exits_2(self):
        code = self._main("--config", self.config_path, "--fail-on-expired")
        self.assertEqual(code, 2)
        self.assertIn("immediate rotation", self.stderr.getvalue())

    def test_missing_config_exits_1_with_message(self):
        code = self._main("--config", "/nope.json")
        self.assertEqual(code, 1)
        self.assertIn("not found", self.stderr.getvalue())

    def test_cli_warn_days_overrides_config(self):
        # With a 200-day window even tls-cert-key (168 days left) is a warning.
        self._main("--config", self.config_path, "--warn-days", "200",
                   "--format", "json")
        parsed = json.loads(self.stdout.getvalue())
        self.assertEqual(parsed["summary"], {"expired": 1, "warning": 2,
                                             "ok": 0, "total": 3})

    def test_bad_today_flag_exits_1(self):
        code = self._main("--config", self.config_path, "--today", "junk")
        self.assertEqual(code, 1)
        self.assertIn("invalid reference date", self.stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
