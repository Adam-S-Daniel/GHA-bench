"""Unit tests for the dependency license checker (TDD, stdlib ``unittest``).

These tests are written FIRST (red) and drive the implementation in
``license_checker.py`` (green).  They use ``unittest`` from the standard
library so they run inside the GitHub Actions / ``act`` container with **no
extra installs** (the container ships python3 but not pytest).

The "license lookup" is *mocked* throughout: instead of querying a real
package registry, we inject a plain ``dict`` (the "license database").  This
is the dependency-injection seam the task asks us to mock.
"""

import json
import os
import sys
import tempfile
import unittest

# Make ``license_checker`` importable no matter how the tests are launched
# (``python3 -m unittest discover`` from the repo root, pytest, an IDE, ...).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import license_checker as lc  # noqa: E402


def _write(tmpdir, name, content):
    """Helper: write *content* to ``tmpdir/name`` and return the full path."""
    path = os.path.join(tmpdir, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    return path


class ParseManifestPackageJsonTests(unittest.TestCase):
    """Cycle 1: parsing a npm-style ``package.json`` manifest."""

    def test_extracts_name_and_version_pairs(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = _write(
                tmp,
                "package.json",
                json.dumps(
                    {
                        "name": "demo-app",
                        "version": "1.0.0",
                        "dependencies": {
                            "left-pad": "1.3.0",
                            "lodash": "^4.17.21",
                        },
                    }
                ),
            )
            deps = lc.parse_manifest(manifest)
            # Order-independent comparison of (name, version) pairs.
            self.assertEqual(
                sorted((d.name, d.version) for d in deps),
                [("left-pad", "1.3.0"), ("lodash", "4.17.21")],
            )


class ParseManifestRequirementsTxtTests(unittest.TestCase):
    """Cycle 2: parsing a pip-style ``requirements.txt`` manifest."""

    def test_extracts_pinned_and_ranged_requirements(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = _write(
                tmp,
                "requirements.txt",
                "# a comment\n"
                "requests==2.28.0\n"
                "\n"  # blank line ignored
                "Flask>=2.0.0\n"
                "  pytest == 7.4.0  # inline comment\n"
                "-r other.txt\n",  # pip directive ignored
            )
            deps = lc.parse_manifest(manifest)
            self.assertEqual(
                sorted((d.name, d.version) for d in deps),
                [("Flask", "2.0.0"), ("pytest", "7.4.0"), ("requests", "2.28.0")],
            )


class ParseManifestErrorTests(unittest.TestCase):
    """Cycle 3: graceful, meaningful errors for bad manifests."""

    def test_missing_file_raises_manifest_error(self):
        with self.assertRaises(lc.ManifestError) as ctx:
            lc.parse_manifest("/no/such/file.json")
        self.assertIn("not found", str(ctx.exception).lower())

    def test_malformed_json_raises_manifest_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = _write(tmp, "package.json", "{ this is not json ")
            with self.assertRaises(lc.ManifestError) as ctx:
                lc.parse_manifest(manifest)
            self.assertIn("package.json", str(ctx.exception))

    def test_unsupported_manifest_type_raises_manifest_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest = _write(tmp, "deps.cfg", "whatever")
            with self.assertRaises(lc.ManifestError) as ctx:
                lc.parse_manifest(manifest)
            self.assertIn("unsupported", str(ctx.exception).lower())


class ClassifyTests(unittest.TestCase):
    """Cycle 4: classifying a single license against the allow/deny policy."""

    def setUp(self):
        self.policy = lc.Policy(allow=["MIT", "Apache-2.0"], deny=["GPL-3.0"])

    def test_allowed_license_is_approved(self):
        self.assertEqual(lc.classify("MIT", self.policy), "approved")

    def test_denied_license_is_denied(self):
        self.assertEqual(lc.classify("GPL-3.0", self.policy), "denied")

    def test_unlisted_license_is_unknown(self):
        self.assertEqual(lc.classify("WTFPL", self.policy), "unknown")

    def test_missing_license_is_unknown(self):
        self.assertEqual(lc.classify(None, self.policy), "unknown")
        self.assertEqual(lc.classify("", self.policy), "unknown")

    def test_matching_is_case_insensitive(self):
        self.assertEqual(lc.classify("mit", self.policy), "approved")

    def test_deny_takes_precedence_over_allow(self):
        # A license appearing in BOTH lists must be treated as denied (fail safe).
        policy = lc.Policy(allow=["MIT"], deny=["MIT"])
        self.assertEqual(lc.classify("MIT", policy), "denied")


class LicenseResolverTests(unittest.TestCase):
    """Cycle 5: the *mocked* license lookup (dependency-injection seam)."""

    def test_prefers_name_at_version_then_falls_back_to_name(self):
        db = {"left-pad@1.3.0": "MIT", "lodash": "ISC"}
        resolve = lc.make_license_resolver(db)
        self.assertEqual(resolve("left-pad", "1.3.0"), "MIT")  # exact match
        self.assertEqual(resolve("lodash", "4.17.21"), "ISC")  # name fallback

    def test_unknown_dependency_resolves_to_none(self):
        resolve = lc.make_license_resolver({})
        self.assertIsNone(resolve("ghost", "9.9.9"))


class CheckDependenciesTests(unittest.TestCase):
    """Cycle 6: end-to-end checking with a mocked resolver + summary."""

    def setUp(self):
        self.policy = lc.Policy(allow=["MIT", "Apache-2.0"], deny=["GPL-3.0"])
        self.deps = [
            lc.Dependency("left-pad", "1.3.0"),
            lc.Dependency("copyleft-lib", "2.0.0"),
            lc.Dependency("mystery", "0.1.0"),
        ]
        # Mocked license database: 'mystery' is deliberately absent -> unknown.
        self.resolve = lc.make_license_resolver(
            {"left-pad": "MIT", "copyleft-lib": "GPL-3.0"}
        )

    def test_produces_one_record_per_dependency_with_status(self):
        records = lc.check_dependencies(self.deps, self.resolve, self.policy)
        by_name = {r.name: r for r in records}
        self.assertEqual(by_name["left-pad"].status, "approved")
        self.assertEqual(by_name["left-pad"].license, "MIT")
        self.assertEqual(by_name["copyleft-lib"].status, "denied")
        self.assertEqual(by_name["mystery"].status, "unknown")
        self.assertIsNone(by_name["mystery"].license)

    def test_summary_counts(self):
        records = lc.check_dependencies(self.deps, self.resolve, self.policy)
        summary = lc.summarize(records)
        self.assertEqual(summary["total"], 3)
        self.assertEqual(summary["approved"], 1)
        self.assertEqual(summary["denied"], 1)
        self.assertEqual(summary["unknown"], 1)


class ReportFormattingTests(unittest.TestCase):
    """Cycle 7: rendering the compliance report (text + json)."""

    def setUp(self):
        policy = lc.Policy(allow=["MIT"], deny=["GPL-3.0"])
        deps = [lc.Dependency("left-pad", "1.3.0"), lc.Dependency("bad", "1.0.0")]
        resolve = lc.make_license_resolver({"left-pad": "MIT", "bad": "GPL-3.0"})
        self.records = lc.check_dependencies(deps, resolve, policy)
        self.summary = lc.summarize(self.records)

    def test_text_report_has_machine_readable_summary_line(self):
        text = lc.format_report(self.records, self.summary, fmt="text")
        self.assertIn(
            "LICENSE-CHECK-SUMMARY total=2 approved=1 denied=1 unknown=0", text
        )
        # Per-dependency lines name the dep, its license and bracketed status.
        self.assertIn("left-pad@1.3.0", text)
        self.assertIn("[approved]", text)
        self.assertIn("[denied]", text)

    def test_json_report_round_trips(self):
        text = lc.format_report(self.records, self.summary, fmt="json")
        data = json.loads(text)
        self.assertEqual(data["summary"]["denied"], 1)
        self.assertEqual(len(data["dependencies"]), 2)

    def test_unknown_format_raises(self):
        with self.assertRaises(ValueError):
            lc.format_report(self.records, self.summary, fmt="xml")


class CliTests(unittest.TestCase):
    """Cycle 8: the command-line entry point used by the GitHub Actions job."""

    def _setup_repo(self, tmp, manifest_obj, policy_obj, db_obj):
        man = _write(tmp, "package.json", json.dumps(manifest_obj))
        pol = _write(tmp, "policy.json", json.dumps(policy_obj))
        db = _write(tmp, "licenses.json", json.dumps(db_obj))
        return man, pol, db

    def test_cli_writes_report_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            man, pol, db = self._setup_repo(
                tmp,
                {"dependencies": {"left-pad": "1.3.0"}},
                {"allow": ["MIT"], "deny": []},
                {"left-pad": "MIT"},
            )
            out = os.path.join(tmp, "report.txt")
            code = lc.main(
                [
                    "--manifest", man,
                    "--policy", pol,
                    "--license-db", db,
                    "--format", "text",
                    "--output", out,
                ]
            )
            self.assertEqual(code, 0)
            with open(out, encoding="utf-8") as fh:
                report = fh.read()
            self.assertIn(
                "LICENSE-CHECK-SUMMARY total=1 approved=1 denied=0 unknown=0", report
            )

    def test_cli_fail_on_denied_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as tmp:
            man, pol, db = self._setup_repo(
                tmp,
                {"dependencies": {"bad": "1.0.0"}},
                {"allow": ["MIT"], "deny": ["GPL-3.0"]},
                {"bad": "GPL-3.0"},
            )
            code = lc.main(
                [
                    "--manifest", man,
                    "--policy", pol,
                    "--license-db", db,
                    "--fail-on-denied",
                    "--output", os.path.join(tmp, "out.txt"),  # keep stdout clean
                ]
            )
            self.assertEqual(code, 2)

    def test_cli_missing_manifest_reports_error_and_exits_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, pol, db = self._setup_repo(
                tmp, {"dependencies": {}}, {"allow": [], "deny": []}, {}
            )
            code = lc.main(
                [
                    "--manifest", os.path.join(tmp, "nope.json"),
                    "--policy", pol,
                    "--license-db", db,
                ]
            )
            self.assertEqual(code, 1)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
