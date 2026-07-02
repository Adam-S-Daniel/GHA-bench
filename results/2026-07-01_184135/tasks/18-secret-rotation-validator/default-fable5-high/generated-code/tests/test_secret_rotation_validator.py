"""Unit tests for the secret rotation validator.

Built with red/green TDD: each test (or small group of tests) was written
first, watched to fail, then the minimum implementation was added to
secret_rotation_validator.py to make it pass, followed by refactoring.

The validator never looks at the real clock in tests: every function takes
an explicit `as_of` date, which acts as our "mock clock" and keeps every
test deterministic.
"""

import contextlib
import datetime
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from secret_rotation_validator import (
    ConfigError,
    build_report,
    classify_secret,
    load_config,
    main,
    render_report,
)

FIXTURES = pathlib.Path(__file__).parent / "fixtures"

# A small deterministic fixture used by the report/rendering tests:
# one expired, one warning, one ok secret as of 2026-07-01 (warn_days=14).
AS_OF = datetime.date(2026, 7, 1)
MIXED_SECRETS = [
    {
        "name": "tls-cert",
        "last_rotated": "2026-06-30",
        "rotation_days": 365,  # due 2027-06-30 -> ok (364 days)
        "required_by": ["gateway"],
    },
    {
        "name": "db-password",
        "last_rotated": "2026-01-01",
        "rotation_days": 90,  # due 2026-04-01 -> expired (-91 days)
        "required_by": ["billing", "api"],
    },
    {
        "name": "api-key",
        "last_rotated": "2026-06-11",
        "rotation_days": 30,  # due 2026-07-11 -> warning (10 days)
        "required_by": ["api"],
    },
]


class TestClassifySecret(unittest.TestCase):
    """TDD cycle 1: classify a single secret against an as-of date."""

    def test_secret_past_due_date_is_expired(self):
        # last rotated 2026-01-01 with a 90-day policy -> due 2026-04-01.
        # On 2026-07-01 it is 91 days overdue.
        secret = {
            "name": "db-password",
            "last_rotated": "2026-01-01",
            "rotation_days": 90,
            "required_by": ["billing", "api"],
        }
        result = classify_secret(
            secret,
            as_of=datetime.date(2026, 7, 1),
            warn_days=14,
        )
        self.assertEqual(result["status"], "expired")
        self.assertEqual(result["due_date"], "2026-04-01")
        self.assertEqual(result["days_remaining"], -91)

    def test_secret_due_today_is_expired(self):
        # Boundary: due exactly on as_of means "rotate now" -> expired.
        secret = self._secret(last_rotated="2026-06-01", rotation_days=30)
        result = classify_secret(secret, as_of=datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual(result["status"], "expired")
        self.assertEqual(result["days_remaining"], 0)

    def test_secret_inside_warning_window_is_warning(self):
        secret = self._secret(last_rotated="2026-06-11", rotation_days=30)  # due 2026-07-11
        result = classify_secret(secret, as_of=datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual(result["status"], "warning")
        self.assertEqual(result["days_remaining"], 10)

    def test_secret_on_warning_boundary_is_warning(self):
        # Boundary: days_remaining == warn_days still warns.
        secret = self._secret(last_rotated="2026-06-17", rotation_days=28)  # due 2026-07-15
        result = classify_secret(secret, as_of=datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual(result["status"], "warning")
        self.assertEqual(result["days_remaining"], 14)

    def test_secret_beyond_warning_window_is_ok(self):
        secret = self._secret(last_rotated="2026-06-30", rotation_days=365)  # due 2027-06-30
        result = classify_secret(secret, as_of=datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["days_remaining"], 364)

    def test_classification_carries_secret_metadata(self):
        secret = self._secret(required_by=["api", "worker"])
        result = classify_secret(secret, as_of=datetime.date(2026, 7, 1), warn_days=14)
        self.assertEqual(result["name"], "test-secret")
        self.assertEqual(result["required_by"], ["api", "worker"])
        self.assertEqual(result["last_rotated"], "2026-06-01")

    @staticmethod
    def _secret(name="test-secret", last_rotated="2026-06-01",
                rotation_days=30, required_by=None):
        """Fixture factory so each test only spells out what it cares about."""
        return {
            "name": name,
            "last_rotated": last_rotated,
            "rotation_days": rotation_days,
            "required_by": required_by if required_by is not None else ["api"],
        }


class TestBuildReport(unittest.TestCase):
    """TDD cycle 3: aggregate classified secrets into a grouped report."""

    def setUp(self):
        self.report = build_report(MIXED_SECRETS, as_of=AS_OF, warn_days=14)

    def test_report_records_inputs(self):
        self.assertEqual(self.report["as_of"], "2026-07-01")
        self.assertEqual(self.report["warn_days"], 14)

    def test_report_summary_counts(self):
        self.assertEqual(
            self.report["summary"], {"expired": 1, "warning": 1, "ok": 1}
        )

    def test_report_groups_by_urgency(self):
        groups = self.report["groups"]
        self.assertEqual([s["name"] for s in groups["expired"]], ["db-password"])
        self.assertEqual([s["name"] for s in groups["warning"]], ["api-key"])
        self.assertEqual([s["name"] for s in groups["ok"]], ["tls-cert"])

    def test_groups_sorted_most_urgent_first(self):
        # Two expired secrets: the one that has been overdue longest comes
        # first (smallest days_remaining).
        secrets = [
            {"name": "a", "last_rotated": "2026-06-21", "rotation_days": 5,
             "required_by": []},  # due 2026-06-26 -> -5 days
            {"name": "b", "last_rotated": "2026-05-02", "rotation_days": 10,
             "required_by": []},  # due 2026-05-12 -> -50 days
        ]
        report = build_report(secrets, as_of=AS_OF, warn_days=14)
        self.assertEqual(
            [s["name"] for s in report["groups"]["expired"]], ["b", "a"]
        )

    def test_notification_messages(self):
        expired = self.report["groups"]["expired"][0]
        warning = self.report["groups"]["warning"][0]
        ok = self.report["groups"]["ok"][0]
        self.assertEqual(
            expired["message"],
            "EXPIRED: 'db-password' was due 2026-04-01 (91 days overdue); "
            "rotate immediately. Impacted services: billing, api",
        )
        self.assertEqual(
            warning["message"],
            "WARNING: 'api-key' is due 2026-07-11 (in 10 days). "
            "Impacted services: api",
        )
        self.assertEqual(
            ok["message"],
            "OK: 'tls-cert' is due 2027-06-30 (in 364 days).",
        )

    def test_empty_config_yields_empty_report(self):
        report = build_report([], as_of=AS_OF, warn_days=14)
        self.assertEqual(report["summary"], {"expired": 0, "warning": 0, "ok": 0})
        self.assertEqual(
            report["groups"], {"expired": [], "warning": [], "ok": []}
        )


class TestRenderReport(unittest.TestCase):
    """TDD cycle 4: render a report as a markdown table or JSON."""

    def setUp(self):
        self.report = build_report(MIXED_SECRETS, as_of=AS_OF, warn_days=14)

    def test_markdown_output_exact(self):
        expected = "\n".join([
            "# Secret Rotation Report",
            "",
            "- As of: 2026-07-01",
            "- Warning window: 14 days",
            "- Summary: 1 expired, 1 warning, 1 ok",
            "",
            "| Secret | Status | Last rotated | Due date | Days remaining | Required by |",
            "| --- | --- | --- | --- | --- | --- |",
            "| db-password | EXPIRED | 2026-01-01 | 2026-04-01 | -91 | billing, api |",
            "| api-key | WARNING | 2026-06-11 | 2026-07-11 | 10 | api |",
            "| tls-cert | OK | 2026-06-30 | 2027-06-30 | 364 | gateway |",
            "",
            "## Notifications",
            "",
            "### Expired (1)",
            "",
            "- EXPIRED: 'db-password' was due 2026-04-01 (91 days overdue); "
            "rotate immediately. Impacted services: billing, api",
            "",
            "### Warning (1)",
            "",
            "- WARNING: 'api-key' is due 2026-07-11 (in 10 days). "
            "Impacted services: api",
            "",
            "### Ok (1)",
            "",
            "- OK: 'tls-cert' is due 2027-06-30 (in 364 days).",
        ])
        self.assertEqual(render_report(self.report, "markdown"), expected)

    def test_markdown_empty_group_says_none(self):
        report = build_report([], as_of=AS_OF, warn_days=14)
        output = render_report(report, "markdown")
        self.assertIn("### Expired (0)\n\n- none", output)

    def test_json_output_round_trips(self):
        # JSON output must parse back to exactly the report structure.
        output = render_report(self.report, "json")
        self.assertEqual(json.loads(output), self.report)

    def test_json_output_is_pretty_printed(self):
        output = render_report(self.report, "json")
        self.assertIn('  "as_of": "2026-07-01",', output.splitlines())

    def test_unknown_format_raises_value_error(self):
        with self.assertRaises(ValueError) as ctx:
            render_report(self.report, "xml")
        self.assertIn("Unsupported format 'xml'", str(ctx.exception))


class TestLoadConfig(unittest.TestCase):
    """TDD cycle 5: load + validate config files with meaningful errors."""

    def test_loads_valid_config_fixture(self):
        secrets = load_config(FIXTURES / "valid_config.json")
        self.assertEqual([s["name"] for s in secrets], ["db-password", "api-key"])

    def test_missing_file_error_names_the_path(self):
        with self.assertRaises(ConfigError) as ctx:
            load_config(FIXTURES / "no_such_file.json")
        self.assertIn("Config file not found", str(ctx.exception))
        self.assertIn("no_such_file.json", str(ctx.exception))

    def test_invalid_json_error_is_descriptive(self):
        with self.assertRaises(ConfigError) as ctx:
            load_config(FIXTURES / "invalid_json.json")
        self.assertIn("Invalid JSON", str(ctx.exception))

    def test_top_level_must_have_secrets_list(self):
        self._assert_config_error(
            {"not_secrets": []},
            "must contain a 'secrets' list",
        )

    def test_missing_field_names_secret_and_field(self):
        self._assert_config_error(
            {"secrets": [{"name": "api-key", "rotation_days": 30,
                          "required_by": []}]},
            "Secret #1 ('api-key'): missing required field 'last_rotated'",
        )

    def test_bad_date_is_reported(self):
        self._assert_config_error(
            {"secrets": [{"name": "x", "last_rotated": "2026-13-01",
                          "rotation_days": 30, "required_by": []}]},
            "invalid last_rotated '2026-13-01' (expected YYYY-MM-DD)",
        )

    def test_rotation_days_must_be_positive_integer(self):
        self._assert_config_error(
            {"secrets": [{"name": "x", "last_rotated": "2026-01-01",
                          "rotation_days": 0, "required_by": []}]},
            "rotation_days must be a positive integer",
        )

    def test_required_by_must_be_list_of_strings(self):
        self._assert_config_error(
            {"secrets": [{"name": "x", "last_rotated": "2026-01-01",
                          "rotation_days": 30, "required_by": "api"}]},
            "required_by must be a list of service names",
        )

    def test_duplicate_names_rejected(self):
        secret = {"name": "x", "last_rotated": "2026-01-01",
                  "rotation_days": 30, "required_by": []}
        self._assert_config_error(
            {"secrets": [secret, dict(secret)]},
            "duplicate secret name 'x'",
        )

    def _assert_config_error(self, config, expected_fragment):
        """Write `config` to a temp file and expect load_config to reject it."""
        with tempfile.NamedTemporaryFile(
            "w", suffix=".json", delete=False
        ) as handle:
            json.dump(config, handle)
            path = handle.name
        try:
            with self.assertRaises(ConfigError) as ctx:
                load_config(path)
            self.assertIn(expected_fragment, str(ctx.exception))
        finally:
            pathlib.Path(path).unlink()


class TestCli(unittest.TestCase):
    """TDD cycle 6: command-line interface built on the library functions."""

    CONFIG = str(FIXTURES / "valid_config.json")

    def _run(self, *argv):
        """Run main() in-process, capturing stdout/stderr and the exit code."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_markdown_run_reports_expected_statuses(self):
        code, out, err = self._run(
            "--config", self.CONFIG, "--as-of", "2026-07-01",
            "--warn-days", "14", "--format", "markdown",
        )
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertIn(
            "| db-password | EXPIRED | 2026-01-01 | 2026-04-01 | -91 | billing, api |",
            out,
        )
        self.assertIn(
            "| api-key | WARNING | 2026-06-11 | 2026-07-11 | 10 | api |", out
        )

    def test_json_run_emits_parseable_report(self):
        code, out, _ = self._run(
            "--config", self.CONFIG, "--as-of", "2026-07-01", "--format", "json",
        )
        self.assertEqual(code, 0)
        report = json.loads(out)
        self.assertEqual(report["summary"], {"expired": 1, "warning": 1, "ok": 0})

    def test_as_of_defaults_to_today_via_clock(self):
        # The CLI must consult the injectable clock, never the real date,
        # so behaviour stays testable and deterministic.
        with mock.patch(
            "secret_rotation_validator._today",
            return_value=datetime.date(2026, 7, 1),
        ):
            code, out, _ = self._run(
                "--config", self.CONFIG, "--format", "json"
            )
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["as_of"], "2026-07-01")

    def test_missing_config_exits_1_with_message_on_stderr(self):
        code, out, err = self._run("--config", "does_not_exist.json")
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("error: Config file not found", err)

    def test_invalid_as_of_exits_1(self):
        code, _, err = self._run(
            "--config", self.CONFIG, "--as-of", "not-a-date"
        )
        self.assertEqual(code, 1)
        self.assertIn("error: invalid --as-of 'not-a-date'", err)

    def test_negative_warn_days_exits_1(self):
        code, _, err = self._run(
            "--config", self.CONFIG, "--warn-days", "-3"
        )
        self.assertEqual(code, 1)
        self.assertIn("error: --warn-days must be >= 0", err)


if __name__ == "__main__":
    unittest.main()
