"""Unit tests for the secret rotation validator.

These tests follow a red/green TDD flow: each behaviour was expressed as a
failing test before the corresponding code in ``secret_rotation_validator.py``
was written. They use only the standard library (``unittest``) so that the
exact same suite runs locally and inside the GitHub Actions container without
needing to install anything.

The suite is intentionally deterministic: every test pins a *reference date*
("now") so results never depend on the wall-clock day the tests happen to run.
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import date

# Make the script importable regardless of the directory the tests run from.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import secret_rotation_validator as srv  # noqa: E402


class ClassifySecretTests(unittest.TestCase):
    """Cycle 1: turn a single secret into a status + derived metadata."""

    def _secret(self, **overrides):
        base = {
            "name": "db-password",
            "last_rotated": "2026-01-01",
            "rotation_policy_days": 90,
            "required_by": ["api", "billing"],
        }
        base.update(overrides)
        return base

    def test_expired_when_due_date_is_in_the_past(self):
        # due = 2026-01-01 + 90d = 2026-04-01, reference 2026-06-28 -> 88d overdue
        result = srv.classify_secret(
            self._secret(), now=date(2026, 6, 28), warning_days=14
        )
        self.assertEqual(result["status"], srv.STATUS_EXPIRED)
        self.assertEqual(result["due_date"], "2026-04-01")
        self.assertEqual(result["days_until_due"], -88)
        # Derived metadata is carried through untouched.
        self.assertEqual(result["name"], "db-password")
        self.assertEqual(result["required_by"], ["api", "billing"])

    def test_warning_when_within_the_window(self):
        # due exactly 10 days out (2026-06-28 + 10d), warning window 14 -> warning
        result = srv.classify_secret(
            self._secret(last_rotated="2026-06-28", rotation_policy_days=10),
            now=date(2026, 6, 28),
            warning_days=14,
        )
        self.assertEqual(result["status"], srv.STATUS_WARNING)
        self.assertEqual(result["days_until_due"], 10)

    def test_ok_when_beyond_the_window(self):
        # due 30 days out, warning window 14 -> ok
        result = srv.classify_secret(
            self._secret(last_rotated="2026-06-28", rotation_policy_days=30),
            now=date(2026, 6, 28),
            warning_days=14,
        )
        self.assertEqual(result["status"], srv.STATUS_OK)
        self.assertEqual(result["days_until_due"], 30)

    def test_due_today_is_a_warning_not_expired(self):
        # days_until_due == 0 is "due today", which we treat as a warning.
        result = srv.classify_secret(
            self._secret(last_rotated="2026-06-18", rotation_policy_days=10),
            now=date(2026, 6, 28),
            warning_days=0,
        )
        self.assertEqual(result["days_until_due"], 0)
        self.assertEqual(result["status"], srv.STATUS_WARNING)

    def test_warning_window_is_configurable(self):
        # The same secret flips ok -> warning as the window widens past it.
        secret = self._secret(last_rotated="2026-04-15", rotation_policy_days=90)
        narrow = srv.classify_secret(secret, now=date(2026, 6, 28), warning_days=14)
        wide = srv.classify_secret(secret, now=date(2026, 6, 28), warning_days=120)
        self.assertEqual(narrow["status"], srv.STATUS_OK)
        self.assertEqual(wide["status"], srv.STATUS_WARNING)


MIXED_SECRETS = [
    {"name": "db-primary-password", "last_rotated": "2026-01-01",
     "rotation_policy_days": 90, "required_by": ["api", "billing"]},
    {"name": "api-signing-key", "last_rotated": "2026-03-01",
     "rotation_policy_days": 90, "required_by": ["api"]},
    {"name": "tls-cert", "last_rotated": "2026-04-01",
     "rotation_policy_days": 90, "required_by": ["gateway"]},
    {"name": "oauth-client-secret", "last_rotated": "2026-04-15",
     "rotation_policy_days": 90, "required_by": ["web"]},
    {"name": "backup-encryption-key", "last_rotated": "2026-06-01",
     "rotation_policy_days": 365, "required_by": ["backups"]},
]


class BuildReportTests(unittest.TestCase):
    """Cycle 3: group classified secrets by urgency and summarise counts."""

    def test_groups_and_summary_for_mixed_input(self):
        report = srv.build_report(
            MIXED_SECRETS, now=date(2026, 6, 28), warning_days=14
        )
        self.assertEqual(report["reference_date"], "2026-06-28")
        self.assertEqual(report["warning_days"], 14)
        self.assertEqual(
            report["summary"],
            {"total": 5, "expired": 2, "warning": 1, "ok": 2},
        )
        self.assertEqual(
            [s["name"] for s in report["groups"]["expired"]],
            ["db-primary-password", "api-signing-key"],
        )
        self.assertEqual(
            [s["name"] for s in report["groups"]["warning"]], ["tls-cert"]
        )
        self.assertEqual(
            [s["name"] for s in report["groups"]["ok"]],
            ["oauth-client-secret", "backup-encryption-key"],
        )

    def test_wider_window_moves_secret_from_ok_to_warning(self):
        report = srv.build_report(
            MIXED_SECRETS, now=date(2026, 6, 28), warning_days=120
        )
        self.assertEqual(
            report["summary"],
            {"total": 5, "expired": 2, "warning": 2, "ok": 1},
        )
        self.assertIn(
            "oauth-client-secret",
            [s["name"] for s in report["groups"]["warning"]],
        )

    def test_expired_group_sorted_most_overdue_first(self):
        report = srv.build_report(
            MIXED_SECRETS, now=date(2026, 6, 28), warning_days=14
        )
        overdue = [s["days_until_due"] for s in report["groups"]["expired"]]
        # Most overdue (most negative) first.
        self.assertEqual(overdue, sorted(overdue))

    def test_empty_config_produces_zeroed_summary(self):
        report = srv.build_report([], now=date(2026, 6, 28), warning_days=14)
        self.assertEqual(
            report["summary"], {"total": 0, "expired": 0, "warning": 0, "ok": 0}
        )
        self.assertEqual(report["groups"]["expired"], [])


class RenderMarkdownTests(unittest.TestCase):
    """Cycle 4: render the report as a grouped markdown document with tables."""

    def setUp(self):
        self.report = srv.build_report(
            MIXED_SECRETS, now=date(2026, 6, 28), warning_days=14
        )
        self.md = srv.render_markdown(self.report)

    def test_has_title_and_context_line(self):
        self.assertIn("# Secret Rotation Report", self.md)
        self.assertIn("2026-06-28", self.md)
        self.assertIn("14", self.md)

    def test_summary_counts_present(self):
        self.assertIn("2 expired", self.md)
        self.assertIn("1 warning", self.md)
        self.assertIn("2 ok", self.md)

    def test_section_headers_with_counts(self):
        self.assertIn("## Expired (2)", self.md)
        self.assertIn("## Warning (1)", self.md)
        self.assertIn("## OK (2)", self.md)

    def test_table_has_header_and_secret_rows(self):
        # Markdown table separator row.
        self.assertIn("| --- |", self.md.replace("|---|", "| --- |"))
        self.assertIn("db-primary-password", self.md)
        # required_by services are joined for display.
        self.assertIn("api, billing", self.md)

    def test_empty_group_shows_none_placeholder(self):
        report = srv.build_report([], now=date(2026, 6, 28), warning_days=14)
        md = srv.render_markdown(report)
        self.assertIn("_None_", md)


class RenderJsonTests(unittest.TestCase):
    """Cycle 5: render the report as JSON (pretty and compact)."""

    def setUp(self):
        self.report = srv.build_report(
            MIXED_SECRETS, now=date(2026, 6, 28), warning_days=14
        )

    def test_pretty_json_roundtrips_to_the_report(self):
        text = srv.render_json(self.report, compact=False)
        self.assertIn("\n", text)  # pretty form is multi-line
        parsed = json.loads(text)
        self.assertEqual(parsed["summary"]["expired"], 2)
        self.assertEqual(
            [s["name"] for s in parsed["groups"]["expired"]],
            ["db-primary-password", "api-signing-key"],
        )

    def test_compact_json_is_single_line(self):
        text = srv.render_json(self.report, compact=True)
        self.assertNotIn("\n", text.strip())
        parsed = json.loads(text)
        self.assertEqual(parsed["summary"]["total"], 5)


class LoadConfigTests(unittest.TestCase):
    """Cycle 2: read + validate the JSON config, with helpful error messages."""

    def _write(self, text):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        self.addCleanup(os.remove, path)
        return path

    def test_loads_secrets_from_object_with_secrets_key(self):
        path = self._write(
            json.dumps(
                {
                    "secrets": [
                        {
                            "name": "a",
                            "last_rotated": "2026-01-01",
                            "rotation_policy_days": 30,
                            "required_by": ["svc"],
                        }
                    ]
                }
            )
        )
        secrets = srv.load_config(path)
        self.assertEqual(len(secrets), 1)
        self.assertEqual(secrets[0]["name"], "a")

    def test_loads_secrets_from_bare_list(self):
        path = self._write(
            json.dumps(
                [
                    {
                        "name": "a",
                        "last_rotated": "2026-01-01",
                        "rotation_policy_days": 30,
                    }
                ]
            )
        )
        secrets = srv.load_config(path)
        self.assertEqual(len(secrets), 1)

    def test_missing_file_raises_config_error(self):
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config("/no/such/file-xyz.json")
        self.assertIn("not found", str(ctx.exception).lower())

    def test_invalid_json_raises_config_error(self):
        path = self._write("{not valid json")
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config(path)
        self.assertIn("invalid json", str(ctx.exception).lower())

    def test_missing_required_field_names_the_field_and_secret(self):
        path = self._write(
            json.dumps({"secrets": [{"name": "a", "last_rotated": "2026-01-01"}]})
        )
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config(path)
        msg = str(ctx.exception)
        self.assertIn("rotation_policy_days", msg)
        self.assertIn("a", msg)  # the offending secret is identified

    def test_bad_date_is_reported_with_context(self):
        path = self._write(
            json.dumps(
                {
                    "secrets": [
                        {
                            "name": "a",
                            "last_rotated": "01/01/2026",
                            "rotation_policy_days": 30,
                        }
                    ]
                }
            )
        )
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config(path)
        self.assertIn("last_rotated", str(ctx.exception))

    def test_non_positive_policy_is_rejected(self):
        path = self._write(
            json.dumps(
                {
                    "secrets": [
                        {
                            "name": "a",
                            "last_rotated": "2026-01-01",
                            "rotation_policy_days": 0,
                        }
                    ]
                }
            )
        )
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config(path)
        self.assertIn("rotation_policy_days", str(ctx.exception))

    def test_required_by_must_be_a_list(self):
        path = self._write(
            json.dumps(
                {
                    "secrets": [
                        {
                            "name": "a",
                            "last_rotated": "2026-01-01",
                            "rotation_policy_days": 30,
                            "required_by": "not-a-list",
                        }
                    ]
                }
            )
        )
        with self.assertRaises(srv.ConfigError) as ctx:
            srv.load_config(path)
        self.assertIn("required_by", str(ctx.exception))


class MainCliTests(unittest.TestCase):
    """Cycle 6: the argparse-driven entry point ties everything together."""

    def _config(self, secrets):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as fh:
            json.dump({"secrets": secrets}, fh)
        self.addCleanup(os.remove, path)
        return path

    def _run(self, argv):
        """Run main(), capturing (exit_code, stdout, stderr)."""
        import io
        from contextlib import redirect_stderr, redirect_stdout

        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = srv.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_markdown_is_the_default_format(self):
        path = self._config(MIXED_SECRETS)
        code, out, _ = self._run(["--config", path, "--now", "2026-06-28"])
        self.assertEqual(code, 0)
        self.assertIn("# Secret Rotation Report", out)
        self.assertIn("## Expired (2)", out)

    def test_json_format(self):
        path = self._config(MIXED_SECRETS)
        code, out, _ = self._run(
            ["--config", path, "--now", "2026-06-28", "--format", "json"]
        )
        self.assertEqual(code, 0)
        parsed = json.loads(out)
        self.assertEqual(parsed["summary"], {"total": 5, "expired": 2, "warning": 1, "ok": 2})

    def test_warning_days_flag_changes_classification(self):
        path = self._config(MIXED_SECRETS)
        code, out, _ = self._run(
            ["--config", path, "--now", "2026-06-28",
             "--warning-days", "120", "--format", "json"]
        )
        self.assertEqual(code, 0)
        parsed = json.loads(out)
        self.assertEqual(parsed["summary"]["warning"], 2)
        self.assertEqual(parsed["summary"]["ok"], 1)

    def test_missing_file_exits_1_with_message_on_stderr(self):
        code, out, err = self._run(["--config", "/no/such/file.json"])
        self.assertEqual(code, 1)
        self.assertIn("not found", err.lower())
        self.assertEqual(out, "")  # nothing written to stdout on error

    def test_invalid_config_exits_1(self):
        path = self._config([{"name": "x", "last_rotated": "2026-01-01"}])
        code, _, err = self._run(["--config", path])
        self.assertEqual(code, 1)
        self.assertIn("rotation_policy_days", err)

    def test_negative_warning_days_exits_1(self):
        path = self._config(MIXED_SECRETS)
        code, _, err = self._run(
            ["--config", path, "--now", "2026-06-28", "--warning-days", "-5"]
        )
        self.assertEqual(code, 1)
        self.assertIn("warning", err.lower())

    def test_fail_on_expired_returns_2_when_expired_present(self):
        path = self._config(MIXED_SECRETS)
        code, out, _ = self._run(
            ["--config", path, "--now", "2026-06-28", "--fail-on-expired"]
        )
        # Report is still produced (so CI can see it) but the gate fails the run.
        self.assertEqual(code, 2)
        self.assertIn("## Expired (2)", out)

    def test_fail_on_expired_returns_0_when_none_expired(self):
        ok_only = [
            {"name": "fresh", "last_rotated": "2026-06-28",
             "rotation_policy_days": 365, "required_by": []}
        ]
        path = self._config(ok_only)
        code, _, _ = self._run(
            ["--config", path, "--now", "2026-06-28", "--fail-on-expired"]
        )
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
