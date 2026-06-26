"""
Red/green TDD test suite for the dependency license checker.

Each test was written BEFORE the implementation it exercises. Run with:

    python3 -m unittest discover -s tests -v

We use only the standard library (unittest) so the suite runs in CI without
any pip installs.
"""
import json
import os
import sys
import tempfile
import unittest

# Make the project root importable so `import license_checker` works regardless
# of the directory the test runner is launched from.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import license_checker as lc  # noqa: E402


class TestParseManifest(unittest.TestCase):
    """Cycle 1: extract dependency names + versions from a manifest."""

    def _write(self, name, content):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(content)
        return path

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_parse_package_json(self):
        path = self._write("package.json", json.dumps({
            "name": "demo",
            "dependencies": {"left-pad": "^1.3.0", "lodash": "4.17.21"},
            "devDependencies": {"jest": "~29.0.0"},
        }))
        deps = lc.parse_manifest(path)
        self.assertEqual(deps["left-pad"], "^1.3.0")
        self.assertEqual(deps["lodash"], "4.17.21")
        self.assertEqual(deps["jest"], "~29.0.0")

    def test_parse_requirements_txt(self):
        # requirements.txt: comments, blank lines and version operators must be
        # handled gracefully.
        path = self._write("requirements.txt", "\n".join([
            "# a comment",
            "",
            "requests==2.31.0",
            "flask>=2.0.0",
            "urllib3   # inline comment, no pin",
            "-e .",            # editable install line, should be skipped
        ]))
        deps = lc.parse_manifest(path)
        self.assertEqual(deps["requests"], "2.31.0")
        self.assertEqual(deps["flask"], "2.0.0")
        self.assertEqual(deps["urllib3"], "")
        self.assertNotIn("-e .", deps)

    def test_parse_unknown_extension_raises(self):
        path = self._write("deps.xml", "<deps/>")
        with self.assertRaises(ValueError) as ctx:
            lc.parse_manifest(path)
        self.assertIn("Unsupported manifest", str(ctx.exception))

    def test_parse_missing_file_raises(self):
        with self.assertRaises(FileNotFoundError) as ctx:
            lc.parse_manifest(os.path.join(self.tmp.name, "nope.json"))
        self.assertIn("nope.json", str(ctx.exception))


class TestLicenseLookup(unittest.TestCase):
    """Cycle 3: a mockable license lookup, defaulting to 'unknown'."""

    def test_lookup_from_mock_database(self):
        db = {"lodash": "MIT", "left-pad": "WTFPL"}
        self.assertEqual(lc.lookup_license("lodash", db), "MIT")
        self.assertEqual(lc.lookup_license("left-pad", db), "WTFPL")

    def test_lookup_unknown_dependency_returns_unknown(self):
        self.assertEqual(lc.lookup_license("ghost-pkg", {}), "UNKNOWN")


class TestClassify(unittest.TestCase):
    """Cycle 4: map a license to approved / denied / unknown."""

    def setUp(self):
        self.cfg = {"allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"]}

    def test_allowed_license_is_approved(self):
        self.assertEqual(lc.classify("MIT", self.cfg), "approved")

    def test_denied_license_is_denied(self):
        self.assertEqual(lc.classify("GPL-3.0", self.cfg), "denied")

    def test_unlisted_license_is_unknown(self):
        self.assertEqual(lc.classify("BSD-2-Clause", self.cfg), "unknown")

    def test_unknown_license_string_is_unknown(self):
        self.assertEqual(lc.classify("UNKNOWN", self.cfg), "unknown")

    def test_classification_is_case_insensitive(self):
        self.assertEqual(lc.classify("mit", self.cfg), "approved")


class TestGenerateReport(unittest.TestCase):
    """Cycle 5: assemble the full compliance report."""

    def setUp(self):
        self.deps = {"lodash": "4.17.21", "evil": "1.0.0", "mystery": "0.1.0"}
        self.db = {"lodash": "MIT", "evil": "GPL-3.0"}
        self.cfg = {"allow": ["MIT"], "deny": ["GPL-3.0"]}

    def test_report_has_one_entry_per_dependency(self):
        report = lc.generate_report(self.deps, self.cfg, self.db)
        names = {e["name"] for e in report["dependencies"]}
        self.assertEqual(names, {"lodash", "evil", "mystery"})

    def test_report_entries_have_expected_status(self):
        report = lc.generate_report(self.deps, self.cfg, self.db)
        by_name = {e["name"]: e for e in report["dependencies"]}
        self.assertEqual(by_name["lodash"]["status"], "approved")
        self.assertEqual(by_name["lodash"]["license"], "MIT")
        self.assertEqual(by_name["lodash"]["version"], "4.17.21")
        self.assertEqual(by_name["evil"]["status"], "denied")
        self.assertEqual(by_name["mystery"]["status"], "unknown")
        self.assertEqual(by_name["mystery"]["license"], "UNKNOWN")

    def test_report_summary_counts(self):
        report = lc.generate_report(self.deps, self.cfg, self.db)
        self.assertEqual(report["summary"]["approved"], 1)
        self.assertEqual(report["summary"]["denied"], 1)
        self.assertEqual(report["summary"]["unknown"], 1)
        self.assertEqual(report["summary"]["total"], 3)

    def test_report_compliant_flag_false_when_denied_present(self):
        report = lc.generate_report(self.deps, self.cfg, self.db)
        self.assertFalse(report["compliant"])

    def test_report_compliant_flag_true_when_all_approved(self):
        report = lc.generate_report(
            {"lodash": "4.17.21"}, self.cfg, self.db)
        self.assertTrue(report["compliant"])


class TestMainCli(unittest.TestCase):
    """Cycle 6: the CLI entry point wiring everything together."""

    def _write(self, name, content):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(content)
        return path

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.manifest = self._write("package.json", json.dumps({
            "dependencies": {"lodash": "4.17.21", "evil": "1.0.0"},
        }))
        self.config = self._write("license-config.json", json.dumps({
            "allow": ["MIT"], "deny": ["GPL-3.0"],
        }))
        self.db = self._write("license-db.json", json.dumps({
            "lodash": "MIT", "evil": "GPL-3.0",
        }))
        self.out = os.path.join(self.tmp.name, "report.json")

    def test_main_writes_report_and_returns_nonzero_when_denied(self):
        rc = lc.main([
            "--manifest", self.manifest,
            "--config", self.config,
            "--license-db", self.db,
            "--output", self.out,
        ])
        # A denied dependency means non-compliant -> exit code 1 (CI gate).
        self.assertEqual(rc, 1)
        with open(self.out, encoding="utf-8") as fh:
            report = json.load(fh)
        self.assertFalse(report["compliant"])
        self.assertEqual(report["summary"]["denied"], 1)

    def test_main_returns_zero_when_all_compliant(self):
        manifest = self._write("ok.package.json", json.dumps({
            "dependencies": {"lodash": "4.17.21"},
        }))
        rc = lc.main([
            "--manifest", manifest,
            "--config", self.config,
            "--license-db", self.db,
            "--output", self.out,
        ])
        self.assertEqual(rc, 0)

    def test_main_reports_missing_manifest_gracefully(self):
        rc = lc.main([
            "--manifest", os.path.join(self.tmp.name, "missing.json"),
            "--config", self.config,
            "--license-db", self.db,
            "--output", self.out,
        ])
        # Graceful failure: exit code 2 for usage/IO errors, not a traceback.
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
