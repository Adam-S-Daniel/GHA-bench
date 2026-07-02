#!/usr/bin/env python3
"""
Test Results Aggregator.

Parses test result files from multiple matrix-build runs (JUnit XML and/or a
simple JSON report format), aggregates totals across all runs, detects flaky
tests (tests that passed in at least one run and failed in at least one other
run), and renders a Markdown summary suitable for a GitHub Actions job
summary ($GITHUB_STEP_SUMMARY).

Usage:
    python3 aggregator.py <result-file> [<result-file> ...] [--stats-out FILE]

Each input file is treated as one "run" (e.g. one cell of a CI matrix such as
os x language-version). The run's identity, used for flaky-test grouping and
the per-run breakdown table, is derived from the file's basename.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field


class AggregatorError(Exception):
    """Raised for any user-facing error: bad input files, unsupported
    formats, or malformed content. Callers should print str(err) and exit
    non-zero rather than showing a raw traceback."""


# --------------------------------------------------------------------------
# Data model
# --------------------------------------------------------------------------

# Statuses are normalized to these four values regardless of source format.
VALID_STATUSES = {"passed", "failed", "skipped", "error"}
# error is treated as a failure for pass/fail purposes, but kept distinct so
# a caller can tell "the test asserted something wrong" apart from "the test
# harness itself blew up".
FAILING_STATUSES = {"failed", "error"}


@dataclass
class TestCase:
    name: str
    classname: str
    status: str  # one of VALID_STATUSES
    duration: float = 0.0
    message: str | None = None

    @property
    def key(self) -> tuple[str, str]:
        """Identity used to match the same test across different runs."""
        return (self.classname, self.name)


@dataclass
class RunResult:
    run_id: str
    source_path: str
    test_cases: list[TestCase] = field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.test_cases)

    @property
    def passed(self) -> int:
        return sum(1 for t in self.test_cases if t.status == "passed")

    @property
    def failed(self) -> int:
        return sum(1 for t in self.test_cases if t.status in FAILING_STATUSES)

    @property
    def skipped(self) -> int:
        return sum(1 for t in self.test_cases if t.status == "skipped")

    @property
    def duration(self) -> float:
        return sum(t.duration for t in self.test_cases)


@dataclass
class FlakyTest:
    name: str
    classname: str
    statuses: list[str]  # one entry per run, in run order


@dataclass
class AggregateReport:
    runs: list[RunResult]
    flaky_tests: list[FlakyTest]

    @property
    def total(self) -> int:
        return sum(r.total for r in self.runs)

    @property
    def passed(self) -> int:
        return sum(r.passed for r in self.runs)

    @property
    def failed(self) -> int:
        return sum(r.failed for r in self.runs)

    @property
    def skipped(self) -> int:
        return sum(r.skipped for r in self.runs)

    @property
    def duration(self) -> float:
        return sum(r.duration for r in self.runs)

    @property
    def unique_tests(self) -> int:
        keys = set()
        for r in self.runs:
            for t in r.test_cases:
                keys.add(t.key)
        return len(keys)

    @property
    def pass_rate(self) -> float | None:
        """Percentage of test executions that passed, or None if there were
        no test executions at all (avoids a division by zero)."""
        if self.total == 0:
            return None
        return 100.0 * self.passed / self.total


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

def _run_id_from_path(path: str) -> str:
    """Derive a human-readable run identifier from a file path, e.g.
    'fixtures/run-1-ubuntu.xml' -> 'run-1-ubuntu'."""
    return os.path.splitext(os.path.basename(path))[0]


def parse_junit_xml(path: str) -> RunResult:
    """Parse a JUnit-style XML report. Accepts both a <testsuites> root
    containing one or more <testsuite> elements, and a bare <testsuite> root
    (both forms are common in the wild)."""
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise AggregatorError(f"Failed to parse JUnit XML file '{path}': {exc}") from exc

    root = tree.getroot()
    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")

    test_cases: list[TestCase] = []
    for suite in suites:
        for tc_el in suite.findall("testcase"):
            name = tc_el.get("name", "")
            classname = tc_el.get("classname", "")
            try:
                duration = float(tc_el.get("time", "0") or 0)
            except ValueError:
                duration = 0.0

            failure_el = tc_el.find("failure")
            error_el = tc_el.find("error")
            skipped_el = tc_el.find("skipped")

            if error_el is not None:
                status = "error"
                message = error_el.get("message") or (error_el.text or "").strip() or None
            elif failure_el is not None:
                status = "failed"
                message = failure_el.get("message") or (failure_el.text or "").strip() or None
            elif skipped_el is not None:
                status = "skipped"
                message = skipped_el.get("message") or None
            else:
                status = "passed"
                message = None

            test_cases.append(TestCase(name=name, classname=classname, status=status,
                                        duration=duration, message=message))

    return RunResult(run_id=_run_id_from_path(path), source_path=path, test_cases=test_cases)


def parse_json_report(path: str) -> RunResult:
    """Parse the aggregator's simple JSON report format:

    {
      "suite": "...",
      "run_id": "...",           # optional, informational only
      "tests": [
        {"classname": "...", "name": "...", "status": "passed|failed|skipped|error",
         "duration": 0.0, "message": "..." (optional)}
      ]
    }
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        raise AggregatorError(f"Failed to parse JSON report file '{path}': {exc}") from exc

    if not isinstance(data, dict) or "tests" not in data:
        raise AggregatorError(
            f"Invalid JSON report file '{path}': expected an object with a 'tests' array"
        )

    test_cases: list[TestCase] = []
    for i, entry in enumerate(data["tests"]):
        if "name" not in entry or "status" not in entry:
            raise AggregatorError(
                f"Invalid JSON report file '{path}': test entry #{i} is missing 'name' or 'status'"
            )
        status = entry["status"]
        if status not in VALID_STATUSES:
            raise AggregatorError(
                f"Invalid JSON report file '{path}': test entry #{i} has unknown status '{status}' "
                f"(expected one of {sorted(VALID_STATUSES)})"
            )
        test_cases.append(TestCase(
            name=entry["name"],
            classname=entry.get("classname", ""),
            status=status,
            duration=float(entry.get("duration", 0.0)),
            message=entry.get("message"),
        ))

    return RunResult(run_id=_run_id_from_path(path), source_path=path, test_cases=test_cases)


def parse_file(path: str) -> RunResult:
    """Dispatch to the right parser based on file extension, falling back to
    sniffing the leading content for extensionless/misnamed files."""
    if not os.path.isfile(path):
        raise AggregatorError(f"Test result file not found: '{path}'")

    ext = os.path.splitext(path)[1].lower()
    if ext == ".xml":
        return parse_junit_xml(path)
    if ext == ".json":
        return parse_json_report(path)

    # Unknown extension: sniff the first non-whitespace character.
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        head = fh.read(256).lstrip()
    if head.startswith("<"):
        return parse_junit_xml(path)
    if head.startswith("{") or head.startswith("["):
        return parse_json_report(path)

    raise AggregatorError(
        f"Unsupported test result format for '{path}': expected a .xml (JUnit) "
        f"or .json file"
    )


# --------------------------------------------------------------------------
# Aggregation
# --------------------------------------------------------------------------

def aggregate(runs: list[RunResult]) -> AggregateReport:
    """Combine per-run results into totals and detect flaky tests.

    A test is considered flaky when, across the given runs, it has at least
    one 'passed' result AND at least one failing ('failed' or 'error')
    result. Skips don't by themselves make a test flaky.
    """
    if not runs:
        raise AggregatorError("No test result files were provided to aggregate")

    # key -> (name, classname, [status per run in run order, '(not run)' if absent])
    statuses_by_key: dict[tuple[str, str], list[str]] = {}
    for run in runs:
        seen_in_run: dict[tuple[str, str], str] = {}
        for tc in run.test_cases:
            # If a test appears more than once in the same run, treat any
            # failure as the run's verdict for that test (fail-dominant).
            existing = seen_in_run.get(tc.key)
            if existing is None or (existing == "passed" and tc.status in FAILING_STATUSES):
                seen_in_run[tc.key] = tc.status
        for key, status in seen_in_run.items():
            statuses_by_key.setdefault(key, []).append(status)

    flaky_tests: list[FlakyTest] = []
    for (classname, name), statuses in statuses_by_key.items():
        has_pass = "passed" in statuses
        has_fail = any(s in FAILING_STATUSES for s in statuses)
        if has_pass and has_fail:
            flaky_tests.append(FlakyTest(name=name, classname=classname, statuses=statuses))

    # Deterministic ordering: by classname then name.
    flaky_tests.sort(key=lambda f: (f.classname, f.name))

    return AggregateReport(runs=runs, flaky_tests=flaky_tests)


# --------------------------------------------------------------------------
# Markdown rendering
# --------------------------------------------------------------------------

def _fmt_duration(seconds: float) -> str:
    return f"{seconds:.3f}s"


def _fmt_pass_rate(rate: float | None) -> str:
    return "N/A" if rate is None else f"{rate:.1f}%"


def generate_markdown(report: AggregateReport) -> str:
    """Render the aggregate report as a GitHub-flavored Markdown summary."""
    lines: list[str] = []
    lines.append("## Test Results Summary")
    lines.append("")
    lines.append(f"**Matrix runs aggregated:** {len(report.runs)}")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|---|---|")
    lines.append(f"| Total test executions | {report.total} |")
    lines.append(f"| Unique tests | {report.unique_tests} |")
    lines.append(f"| ✅ Passed | {report.passed} |")
    lines.append(f"| ❌ Failed | {report.failed} |")
    lines.append(f"| ⏭️ Skipped | {report.skipped} |")
    lines.append(f"| ⚠️ Flaky | {len(report.flaky_tests)} |")
    lines.append(f"| Pass rate | {_fmt_pass_rate(report.pass_rate)} |")
    lines.append(f"| Total duration | {_fmt_duration(report.duration)} |")
    lines.append("")

    lines.append("### Per-run breakdown")
    lines.append("")
    lines.append("| Run | Total | Passed | Failed | Skipped | Duration |")
    lines.append("|---|---|---|---|---|---|")
    for run in report.runs:
        lines.append(
            f"| {run.run_id} | {run.total} | {run.passed} | {run.failed} | "
            f"{run.skipped} | {_fmt_duration(run.duration)} |"
        )
    lines.append("")

    lines.append("### Flaky tests")
    lines.append("")
    if report.flaky_tests:
        lines.append("| Test | Classname | Results across runs |")
        lines.append("|---|---|---|")
        for flaky in report.flaky_tests:
            lines.append(f"| {flaky.name} | {flaky.classname} | {', '.join(flaky.statuses)} |")
    else:
        lines.append("No flaky tests detected.")
    lines.append("")

    failed_cases = [
        tc for run in report.runs for tc in run.test_cases if tc.status in FAILING_STATUSES
    ]
    lines.append("### Failed tests")
    lines.append("")
    if failed_cases:
        lines.append("| Run | Test | Message |")
        lines.append("|---|---|---|")
        for run in report.runs:
            for tc in run.test_cases:
                if tc.status in FAILING_STATUSES:
                    msg = (tc.message or "").replace("\n", " ").replace("|", "\\|")
                    lines.append(f"| {run.run_id} | {tc.name} | {msg} |")
    else:
        lines.append("No failed tests.")
    lines.append("")

    return "\n".join(lines)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def _write_stats_file(report: AggregateReport, path: str) -> None:
    stats = {
        "total": report.total,
        "unique_tests": report.unique_tests,
        "passed": report.passed,
        "failed": report.failed,
        "skipped": report.skipped,
        "flaky": len(report.flaky_tests),
        "pass_rate": None if report.pass_rate is None else round(report.pass_rate, 1),
        "duration": round(report.duration, 3),
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=2)
        fh.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Aggregate JUnit XML / JSON test result files into a Markdown summary."
    )
    parser.add_argument("files", nargs="+", help="Test result files (.xml or .json)")
    parser.add_argument(
        "--stats-out", metavar="FILE",
        help="Also write a machine-readable JSON stats summary to FILE",
    )
    args = parser.parse_args(argv)

    try:
        runs = [parse_file(path) for path in sorted(args.files)]
        report = aggregate(runs)
    except AggregatorError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    markdown = generate_markdown(report)
    print(markdown)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write(markdown)
            fh.write("\n")

    if args.stats_out:
        _write_stats_file(report, args.stats_out)

    return 0


if __name__ == "__main__":
    sys.exit(main())
