"""Unit tests for the test-results aggregator.

Built with red/green TDD: each test class below was written BEFORE the
corresponding production code in aggregator.py, watched fail (RED), then the
minimum code was added to make it pass (GREEN), followed by refactoring.

Only the Python standard library is used (unittest) so these tests run
unmodified inside the act/GitHub Actions container without pip installs.
"""

import unittest
from pathlib import Path

# Repo root (tests/ lives one level below it).
ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"


class TestJUnitXmlParsing(unittest.TestCase):
    """TDD cycle 1: parse a single JUnit XML file into TestResult records."""

    def test_parses_statuses_names_and_durations(self):
        from aggregator import parse_junit_xml

        results = parse_junit_xml(FIXTURES / "case1-matrix-flaky" / "junit-ubuntu.xml")

        self.assertEqual(len(results), 4)
        by_id = {r.test_id: r for r in results}
        self.assertEqual(
            set(by_id),
            {
                "shop.tests::test_login",
                "shop.tests::test_checkout",
                "shop.tests::test_flaky_search",
                "shop.tests::test_skip_on_linux",
            },
        )
        self.assertEqual(by_id["shop.tests::test_login"].status, "passed")
        self.assertEqual(by_id["shop.tests::test_flaky_search"].status, "failed")
        self.assertEqual(by_id["shop.tests::test_skip_on_linux"].status, "skipped")
        self.assertAlmostEqual(by_id["shop.tests::test_flaky_search"].duration, 2.0)
        # Failure message is preserved for reporting.
        self.assertIn("search index", by_id["shop.tests::test_flaky_search"].message)


class TestJsonParsing(unittest.TestCase):
    """TDD cycle 2: parse the JSON results format into the same records."""

    def test_parses_json_results_file(self):
        from aggregator import parse_json_results

        results = parse_json_results(FIXTURES / "case1-matrix-flaky" / "results-macos.json")

        self.assertEqual(len(results), 4)
        by_id = {r.test_id: r for r in results}
        self.assertEqual(by_id["shop.tests::test_checkout"].status, "failed")
        self.assertEqual(by_id["shop.tests::test_checkout"].message,
                         "TimeoutError: payment gateway stub timed out")
        self.assertEqual(by_id["shop.tests::test_extra_mac_only"].status, "passed")
        self.assertAlmostEqual(by_id["shop.tests::test_flaky_search"].duration, 2.1)

    def test_rejects_invalid_status(self):
        """A JSON file with an unknown status must raise a clear error."""
        import json
        import tempfile

        from aggregator import AggregatorError, parse_json_results

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            json.dump({"tests": [{"name": "t", "status": "exploded"}]}, fh)
        with self.assertRaisesRegex(AggregatorError, "exploded"):
            parse_json_results(fh.name)


class TestAggregation(unittest.TestCase):
    """TDD cycle 3: aggregate multiple run files (a simulated matrix build)."""

    def test_aggregates_directory_totals_and_flaky_tests(self):
        from aggregator import aggregate_directory

        summary = aggregate_directory(FIXTURES / "case1-matrix-flaky")

        # 3 runs: ubuntu (4 tests), windows (4 tests), macos (4 tests).
        self.assertEqual(len(summary.runs), 3)
        self.assertEqual(summary.total, 12)
        self.assertEqual(summary.passed, 7)
        self.assertEqual(summary.failed, 3)
        self.assertEqual(summary.skipped, 2)
        self.assertAlmostEqual(summary.duration, 11.1, places=6)
        # test_checkout passed on ubuntu but failed on windows+macos;
        # test_flaky_search failed on ubuntu but passed on windows+macos.
        self.assertEqual(
            [f.test_id for f in summary.flaky],
            ["shop.tests::test_checkout", "shop.tests::test_flaky_search"],
        )
        checkout = summary.flaky[0]
        self.assertEqual(sorted(checkout.passed_in), ["junit-ubuntu.xml"])
        self.assertEqual(sorted(checkout.failed_in),
                         ["junit-windows.xml", "results-macos.json"])

    def test_all_green_directory_has_no_flaky_tests(self):
        from aggregator import aggregate_directory

        summary = aggregate_directory(FIXTURES / "case2-all-green")

        self.assertEqual((summary.total, summary.passed, summary.failed, summary.skipped),
                         (6, 5, 0, 1))
        self.assertAlmostEqual(summary.duration, 1.5, places=6)
        self.assertEqual(summary.flaky, [])

    def test_consistently_failing_test_is_not_flaky(self):
        """Failing everywhere is broken, not flaky — must not be flagged."""
        from aggregator import RunResult, TestResult, aggregate_runs

        runs = [
            RunResult("a.xml", [TestResult("t", status="failed")]),
            RunResult("b.xml", [TestResult("t", status="failed")]),
        ]
        self.assertEqual(aggregate_runs(runs).flaky, [])


class TestErrorHandling(unittest.TestCase):
    """TDD cycle 3b: meaningful errors for bad input."""

    def test_malformed_xml_raises_meaningful_error(self):
        from aggregator import AggregatorError, parse_junit_xml

        with self.assertRaisesRegex(AggregatorError, "not valid XML"):
            parse_junit_xml(FIXTURES / "malformed" / "bad.xml")

    def test_malformed_json_raises_meaningful_error(self):
        from aggregator import AggregatorError, parse_json_results

        with self.assertRaisesRegex(AggregatorError, "not valid JSON"):
            parse_json_results(FIXTURES / "malformed" / "bad.json")

    def test_missing_directory_raises(self):
        from aggregator import AggregatorError, aggregate_directory

        with self.assertRaisesRegex(AggregatorError, "no such directory"):
            aggregate_directory(FIXTURES / "does-not-exist")

    def test_directory_without_result_files_raises(self):
        import tempfile

        from aggregator import AggregatorError, aggregate_directory

        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(AggregatorError, "no test result files"):
                aggregate_directory(tmp)


class TestMarkdownSummary(unittest.TestCase):
    """TDD cycle 4: render a GitHub-Actions-ready markdown summary."""

    def test_markdown_contains_totals_flaky_and_per_run_tables(self):
        from aggregator import aggregate_directory, render_markdown

        md = render_markdown(aggregate_directory(FIXTURES / "case1-matrix-flaky"))

        self.assertIn("# 🧪 Test Results Summary", md)
        # Totals table rows (exact cell values).
        self.assertIn("| ✅ Passed | 7 |", md)
        self.assertIn("| ❌ Failed | 3 |", md)
        self.assertIn("| ⏭️ Skipped | 2 |", md)
        self.assertIn("| **Total** | **12** |", md)
        self.assertIn("**Total duration:** 11.10s", md)
        # Flaky section lists both flaky tests with where they passed/failed.
        self.assertIn("## ⚠️ Flaky tests (2)", md)
        self.assertIn("`shop.tests::test_checkout`", md)
        self.assertIn("`shop.tests::test_flaky_search`", md)
        self.assertIn("junit-ubuntu.xml", md)
        # Per-run breakdown includes each source file.
        self.assertIn("## Per-run breakdown", md)
        self.assertIn("| results-macos.json | 3 | 1 | 0 | 4.00s |", md)

    def test_markdown_all_green(self):
        from aggregator import aggregate_directory, render_markdown

        md = render_markdown(aggregate_directory(FIXTURES / "case2-all-green"))

        self.assertIn("No flaky tests detected", md)
        self.assertIn("| ✅ Passed | 5 |", md)


class TestCli(unittest.TestCase):
    """TDD cycle 5: command-line entry point.

    stdout carries stable machine-readable lines (RESULT/FLAKY) that the CI
    harness asserts on; the markdown goes to --output for the job summary.
    """

    def test_cli_writes_markdown_and_prints_result_line(self):
        import io
        import tempfile
        from contextlib import redirect_stdout

        from aggregator import main

        with tempfile.TemporaryDirectory() as tmp:
            out_md = Path(tmp) / "summary.md"
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = main([str(FIXTURES / "case1-matrix-flaky"),
                             "--output", str(out_md)])
            self.assertEqual(code, 0)
            stdout = buf.getvalue()
            self.assertIn(
                "RESULT total=12 passed=7 failed=3 skipped=2 duration=11.10 flaky=2",
                stdout,
            )
            self.assertIn("FLAKY shop.tests::test_checkout", stdout)
            self.assertIn("FLAKY shop.tests::test_flaky_search", stdout)
            self.assertIn("| **Total** | **12** |", out_md.read_text(encoding="utf-8"))

    def test_cli_reports_errors_on_stderr_with_exit_code_1(self):
        import io
        from contextlib import redirect_stderr

        from aggregator import main

        buf = io.StringIO()
        with redirect_stderr(buf):
            code = main([str(FIXTURES / "does-not-exist")])
        self.assertEqual(code, 1)
        self.assertIn("no such directory", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
