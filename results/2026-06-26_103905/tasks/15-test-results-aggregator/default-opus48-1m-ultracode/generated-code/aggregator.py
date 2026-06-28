#!/usr/bin/env python3
"""Test Results Aggregator.

Parses test result files in JUnit XML and JSON formats, aggregates them across
multiple files (simulating a CI matrix build), computes totals, detects flaky
tests, and renders a markdown summary suitable for a GitHub Actions job summary.

Only the Python standard library is used so the script runs in any container
that has `python3` available -- no `pip install` step is required.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass

# The three outcomes we normalize every input format down to.
PASSED = "passed"
FAILED = "failed"
SKIPPED = "skipped"
VALID_STATUSES = (PASSED, FAILED, SKIPPED)


class AggregatorError(Exception):
    """Raised for user-facing, recoverable errors (bad input, parse failures)."""


@dataclass
class TestResult:
    """A single test execution from a single result file.

    `classname` + `name` form a stable identity used to correlate the same
    test across matrix legs (which is how flaky tests are detected).
    """

    name: str
    classname: str
    status: str  # one of PASSED / FAILED / SKIPPED
    time: float  # seconds
    source: str  # path of the file this result came from

    @property
    def key(self) -> str:
        """Stable cross-file identity: 'classname::name' (or just 'name')."""
        return f"{self.classname}::{self.name}" if self.classname else self.name


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------
def parse_file(path: str) -> list[TestResult]:
    """Parse one result file, dispatching on its extension."""
    if not os.path.isfile(path):
        raise AggregatorError(f"Test result file not found: {path}")
    ext = os.path.splitext(path)[1].lower()
    if ext == ".xml":
        return _parse_junit(path)
    if ext == ".json":
        return _parse_json(path)
    raise AggregatorError(
        f"Unsupported file type '{ext}' for {path} (expected .xml or .json)"
    )


def _testcase_status(testcase: ET.Element) -> str:
    """Map a JUnit <testcase> to a normalized status.

    Precedence: a failure/error wins over skipped, which wins over passed
    (a bare <testcase> with no child markers is a pass).
    """
    if testcase.find("failure") is not None or testcase.find("error") is not None:
        return FAILED
    if testcase.find("skipped") is not None:
        return SKIPPED
    return PASSED


def _parse_junit(path: str) -> list[TestResult]:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        raise AggregatorError(f"Malformed JUnit XML in {path}: {exc}") from exc

    # Accept either a <testsuites> wrapper or a bare <testsuite> root.
    suites = root.iter("testsuite")
    results: list[TestResult] = []
    for suite in suites:
        for tc in suite.findall("testcase"):
            try:
                time = float(tc.get("time", "0") or "0")
            except ValueError:
                time = 0.0
            results.append(
                TestResult(
                    name=tc.get("name", ""),
                    classname=tc.get("classname", ""),
                    status=_testcase_status(tc),
                    time=time,
                    source=path,
                )
            )
    return results


def _parse_json(path: str) -> list[TestResult]:
    """Parse our simple JSON schema: {"name": ..., "tests": [{...}, ...]}.

    Each test object has: name, optional classname, status (passed/failed/
    skipped) and optional time (seconds).
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        raise AggregatorError(f"Malformed JSON in {path}: {exc}") from exc

    tests = data.get("tests") if isinstance(data, dict) else None
    if not isinstance(tests, list):
        raise AggregatorError(
            f"Invalid JSON in {path}: expected an object with a 'tests' array"
        )

    results: list[TestResult] = []
    for i, t in enumerate(tests):
        if not isinstance(t, dict):
            raise AggregatorError(f"Invalid test entry #{i} in {path}: not an object")
        status = str(t.get("status", "")).lower()
        if status not in VALID_STATUSES:
            raise AggregatorError(
                f"Invalid status '{t.get('status')}' for test "
                f"'{t.get('name', '?')}' in {path} "
                f"(expected one of {', '.join(VALID_STATUSES)})"
            )
        try:
            time = float(t.get("time", 0) or 0)
        except (TypeError, ValueError):
            time = 0.0
        results.append(
            TestResult(
                name=str(t.get("name", "")),
                classname=str(t.get("classname", "")),
                status=status,
                time=time,
                source=path,
            )
        )
    return results


# ---------------------------------------------------------------------------
# Input collection (files and/or directories)
# ---------------------------------------------------------------------------
def _format_of(path: str) -> str:
    return "junit" if path.lower().endswith(".xml") else "json"


def collect_results(paths: list[str]) -> list[TestResult]:
    """Expand the given paths (files or directories) and parse them all.

    Directories are scanned (non-recursively) for *.xml and *.json files so a
    workflow can simply point at an artifacts directory.
    """
    if not paths:
        raise AggregatorError("No input paths given (expected files or directories)")

    files: list[str] = []
    for p in paths:
        if os.path.isdir(p):
            found = [
                os.path.join(p, f)
                for f in sorted(os.listdir(p))
                if f.lower().endswith((".xml", ".json"))
            ]
            files.extend(found)
        elif os.path.isfile(p):
            files.append(p)
        else:
            raise AggregatorError(f"Path not found: {p}")

    if not files:
        raise AggregatorError(
            "No test result files (*.xml / *.json) found in the given paths"
        )

    results: list[TestResult] = []
    for f in files:
        results.extend(parse_file(f))
    return results


# ---------------------------------------------------------------------------
# Aggregation, totals, flaky detection
# ---------------------------------------------------------------------------
@dataclass
class Totals:
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    duration: float = 0.0

    @property
    def total(self) -> int:
        return self.passed + self.failed + self.skipped


@dataclass
class FileSummary:
    name: str  # basename of the source file
    fmt: str  # "junit" or "json"
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    duration: float = 0.0


@dataclass
class FlakyTest:
    key: str
    classname: str
    name: str
    passed: int = 0
    failed: int = 0
    skipped: int = 0


@dataclass
class Summary:
    totals: Totals
    files: list[FileSummary]
    flaky: list[FlakyTest]
    status: str  # "passed" or "failed"


def _bump(counter, status: str) -> None:
    """Increment the field on `counter` matching the given status."""
    setattr(counter, status, getattr(counter, status) + 1)


def aggregate(results: list[TestResult]) -> Summary:
    """Roll individual results up into totals, per-file stats, and flaky tests."""
    totals = Totals()
    per_file: dict[str, FileSummary] = {}
    # per-test outcome tallies keyed by the stable cross-file identity.
    per_test: dict[str, FlakyTest] = {}

    for r in results:
        # Global totals.
        _bump(totals, r.status)
        totals.duration += r.time

        # Per-file breakdown.
        fname = os.path.basename(r.source)
        fs = per_file.get(fname)
        if fs is None:
            fs = FileSummary(name=fname, fmt=_format_of(r.source))
            per_file[fname] = fs
        _bump(fs, r.status)
        fs.duration += r.time

        # Per-test tally (used to spot flaky tests).
        ft = per_test.get(r.key)
        if ft is None:
            ft = FlakyTest(key=r.key, classname=r.classname, name=r.name)
            per_test[r.key] = ft
        _bump(ft, r.status)

    # A test is flaky if it both passed at least once AND failed at least once.
    flaky = sorted(
        (t for t in per_test.values() if t.passed > 0 and t.failed > 0),
        key=lambda t: t.key,
    )

    status = FAILED if totals.failed > 0 else PASSED
    files = [per_file[name] for name in sorted(per_file)]
    return Summary(totals=totals, files=files, flaky=flaky, status=status)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_markdown(summary: Summary) -> str:
    """Render a GitHub-flavored markdown summary."""
    t = summary.totals
    status_badge = "✅ PASSED" if summary.status == PASSED else "❌ FAILED"
    lines: list[str] = []
    lines.append("# Test Results Summary")
    lines.append("")
    lines.append(f"**Overall status:** {status_badge}")
    lines.append("")

    # Totals table.
    lines.append("## Totals")
    lines.append("")
    lines.append("| Result | Count |")
    lines.append("| :--- | ---: |")
    lines.append(f"| ✅ Passed | {t.passed} |")
    lines.append(f"| ❌ Failed | {t.failed} |")
    lines.append(f"| ⏭️ Skipped | {t.skipped} |")
    lines.append(f"| **Total** | {t.total} |")
    lines.append(f"| ⏱️ Duration | {t.duration:.2f}s |")
    lines.append("")

    # Flaky tests.
    lines.append(f"## ⚠️ Flaky Tests ({len(summary.flaky)})")
    lines.append("")
    if summary.flaky:
        lines.append("> Tests that passed in some runs and failed in others.")
        lines.append("")
        lines.append("| Test | ✅ Passed | ❌ Failed | ⏭️ Skipped |")
        lines.append("| :--- | ---: | ---: | ---: |")
        for f in summary.flaky:
            lines.append(f"| `{f.key}` | {f.passed} | {f.failed} | {f.skipped} |")
    else:
        lines.append("✅ No flaky tests detected.")
    lines.append("")

    # Per-file breakdown.
    lines.append("## 📂 Per-file Results")
    lines.append("")
    lines.append("| File | Format | ✅ Passed | ❌ Failed | ⏭️ Skipped | ⏱️ Duration |")
    lines.append("| :--- | :--- | ---: | ---: | ---: | ---: |")
    for f in summary.files:
        lines.append(
            f"| {f.name} | {f.fmt} | {f.passed} | {f.failed} | "
            f"{f.skipped} | {f.duration:.2f}s |"
        )
    lines.append("")
    return "\n".join(lines)


def render_json(summary: Summary) -> str:
    """Render a compact machine-readable JSON document (for CI verification)."""
    t = summary.totals
    payload = {
        "status": summary.status,
        "totals": {
            "passed": t.passed,
            "failed": t.failed,
            "skipped": t.skipped,
            "total": t.total,
            "duration": round(t.duration, 3),
        },
        "flaky": [f.key for f in summary.flaky],
        "flaky_details": [
            {
                "key": f.key,
                "passed": f.passed,
                "failed": f.failed,
                "skipped": f.skipped,
            }
            for f in summary.flaky
        ],
        "files": [
            {
                "name": f.name,
                "format": f.fmt,
                "passed": f.passed,
                "failed": f.failed,
                "skipped": f.skipped,
                "duration": round(f.duration, 3),
            }
            for f in summary.files
        ],
    }
    return json.dumps(payload, indent=2)


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="aggregator.py",
        description="Aggregate JUnit XML / JSON test results into a summary.",
    )
    p.add_argument(
        "paths",
        nargs="*",
        help="Result files (*.xml / *.json) and/or directories to scan.",
    )
    p.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="Output format (default: markdown).",
    )
    p.add_argument("--output", help="Write output to this file instead of stdout.")
    p.add_argument(
        "--validate",
        action="store_true",
        help="Only parse the given files and report; exit non-zero on parse error.",
    )
    p.add_argument(
        "--fail-on-failure",
        action="store_true",
        help="Exit with code 1 if any test failed (off by default: report-only).",
    )
    return p


def _run_validate(paths: list[str]) -> int:
    """Validate that each given file parses, printing a one-line report each."""
    if not paths:
        raise AggregatorError("--validate requires at least one file path")
    for p in paths:
        results = parse_file(p)
        print(f"OK: {p} ({len(results)} tests)")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.validate:
            return _run_validate(args.paths)

        summary = aggregate(collect_results(args.paths))
        rendered = (
            render_json(summary)
            if args.format == "json"
            else render_markdown(summary)
        )
        if args.output:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(rendered + "\n")
            print(f"Wrote {args.format} summary to {args.output}")
        else:
            print(rendered)

        if args.fail_on_failure and summary.status == FAILED:
            return 1
        return 0
    except AggregatorError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
