"""Test result aggregator: parses JUnit XML and JSON test result files,
aggregates across multiple runs (matrix build simulation), computes totals,
detects flaky tests, and renders a GitHub Actions job summary in Markdown.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass


@dataclass
class TestCaseResult:
    """A single test case's outcome within one run/file."""

    __test__ = False  # tell pytest this dataclass is not a test class

    classname: str
    name: str
    status: str  # "passed" | "failed" | "skipped"
    duration: float
    message: str | None = None
    source: str = ""  # originating file, filled in by caller

    @property
    def full_name(self) -> str:
        return f"{self.classname}::{self.name}"


def parse_junit_xml(path: str) -> list[TestCaseResult]:
    """Parse a JUnit-style XML file into a list of TestCaseResult.

    Raises FileNotFoundError with a clear message if the file is missing,
    and ValueError if the XML cannot be parsed as a testsuite.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"JUnit XML file not found: {path}")

    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        raise ValueError(f"Invalid JUnit XML in {path}: {e}") from e

    root = tree.getroot()
    # Some JUnit files wrap suites in <testsuites>; normalize to a flat list.
    testcases = root.iter("testcase")

    results: list[TestCaseResult] = []
    for tc in testcases:
        classname = tc.get("classname", "")
        name = tc.get("name", "")
        duration = float(tc.get("time", "0") or 0)

        status = "passed"
        message = None
        failure = tc.find("failure")
        error = tc.find("error")
        skipped = tc.find("skipped")
        if failure is not None:
            status = "failed"
            message = failure.get("message") or (failure.text or "").strip() or None
        elif error is not None:
            status = "failed"
            message = error.get("message") or (error.text or "").strip() or None
        elif skipped is not None:
            status = "skipped"
            message = skipped.get("message") or None

        results.append(
            TestCaseResult(
                classname=classname,
                name=name,
                status=status,
                duration=duration,
                message=message,
                source=path,
            )
        )

    return results


@dataclass
class Totals:
    """Aggregate pass/fail/skip counts and total duration across all runs."""

    total: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    duration: float = 0.0


def load_all_results(paths: list[str]) -> list[TestCaseResult]:
    """Load and combine results from a mix of JUnit XML and JSON files,
    dispatching on file extension. Raises ValueError for unsupported extensions.
    """
    all_results: list[TestCaseResult] = []
    for path in paths:
        ext = os.path.splitext(path)[1].lower()
        if ext == ".xml":
            all_results.extend(parse_junit_xml(path))
        elif ext == ".json":
            all_results.extend(parse_json_results(path))
        else:
            raise ValueError(f"Unsupported test result file extension: {path}")
    return all_results


def aggregate_results(results: list[TestCaseResult]) -> Totals:
    """Sum pass/fail/skip counts and durations across every test case entry
    (one entry per test per run, so re-running the same test counts each time).
    """
    totals = Totals()
    for r in results:
        totals.total += 1
        totals.duration += r.duration
        if r.status == "passed":
            totals.passed += 1
        elif r.status == "failed":
            totals.failed += 1
        elif r.status == "skipped":
            totals.skipped += 1
    return totals


def detect_flaky_tests(results: list[TestCaseResult]) -> list[TestCaseResult]:
    """Identify tests that both passed and failed across the given runs.

    Returns one representative TestCaseResult per flaky test (the most recent
    entry encountered), for use in reporting.
    """
    statuses_by_test: dict[str, set[str]] = {}
    latest_by_test: dict[str, TestCaseResult] = {}
    for r in results:
        statuses_by_test.setdefault(r.full_name, set()).add(r.status)
        latest_by_test[r.full_name] = r

    flaky = [
        latest_by_test[name]
        for name, statuses in statuses_by_test.items()
        if "passed" in statuses and "failed" in statuses
    ]
    flaky.sort(key=lambda r: r.full_name)
    return flaky


def render_markdown_summary(
    totals: Totals, flaky: list[TestCaseResult], num_files: int
) -> str:
    """Render a Markdown report suitable for $GITHUB_STEP_SUMMARY."""
    status_emoji = "✅" if totals.failed == 0 else "❌"

    lines = [
        "# Test Results Summary",
        "",
        f"{status_emoji} Aggregated from {num_files} files.",
        "",
        "| Metric | Count |",
        "| --- | --- |",
        f"| Total | {totals.total} |",
        f"| Passed | {totals.passed} |",
        f"| Failed | {totals.failed} |",
        f"| Skipped | {totals.skipped} |",
        f"| Duration (s) | {totals.duration:.3f} |",
        "",
    ]

    if flaky:
        lines.append("## Flaky Tests")
        lines.append("")
        lines.append("| Test | Last Status | Message |")
        lines.append("| --- | --- | --- |")
        for t in flaky:
            msg = (t.message or "").replace("\n", " ").replace("|", "\\|")
            lines.append(f"| {t.full_name} | {t.status} | {msg} |")
        lines.append("")
    else:
        lines.append("No flaky tests detected.")
        lines.append("")

    return "\n".join(lines)


def parse_json_results(path: str) -> list[TestCaseResult]:
    """Parse our JSON test-result format:
    {"suiteName": str, "tests": [{"classname", "name", "status", "duration", "message"?}]}

    Raises FileNotFoundError if missing, ValueError if malformed.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"JSON results file not found: {path}")

    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in {path}: {e}") from e

    results: list[TestCaseResult] = []
    for tc in data.get("tests", []):
        results.append(
            TestCaseResult(
                classname=tc.get("classname", ""),
                name=tc.get("name", ""),
                status=tc.get("status", "passed"),
                duration=float(tc.get("duration", 0) or 0),
                message=tc.get("message"),
                source=path,
            )
        )

    return results


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: parses input files, aggregates results, writes a
    Markdown summary, and returns an exit code (0 if all tests passed,
    1 if any failed, 2 on an input/parsing error).
    """
    parser = argparse.ArgumentParser(
        description="Aggregate JUnit XML and JSON test result files into a Markdown summary."
    )
    parser.add_argument("files", nargs="+", help="Test result files (.xml or .json)")
    parser.add_argument(
        "--output", required=True, help="Path to write the Markdown summary to"
    )
    args = parser.parse_args(argv)

    try:
        results = load_all_results(args.files)
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2

    totals = aggregate_results(results)
    flaky = detect_flaky_tests(results)
    summary = render_markdown_summary(totals, flaky, num_files=len(args.files))

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(summary)

    return 1 if totals.failed > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
