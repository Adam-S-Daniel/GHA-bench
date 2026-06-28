#!/usr/bin/env python3
"""Aggregate test results from multiple files (JUnit XML + JSON) into a
GitHub-Actions-ready markdown summary.

The tool simulates a matrix build: each input file is treated as one "run".
Across all runs it computes totals (passed/failed/skipped/duration) and detects
*flaky* tests -- tests that passed in at least one run and failed in at least one
other run.

Design notes
------------
* Every parsed test is normalised into a small ``TestCase`` record so the rest of
  the pipeline does not care which on-disk format it came from.
* ``status`` is normalised to exactly one of ``passed`` / ``failed`` / ``skipped``.
  JUnit ``<error>`` is folded into ``failed``; common JSON aliases (``pass``,
  ``FAIL``, ``error``, ``skip``...) are normalised too.
* Errors are surfaced with the offending file name so CI logs are actionable.
"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


# A single test execution, normalised across input formats. ``run`` records which
# file/run it came from so flaky detection can compare results across runs.
@dataclass(frozen=True)
class TestCase:
    __test__ = False  # tell pytest this is data, not a test class
    classname: str
    name: str
    status: str  # one of: passed, failed, skipped
    duration: float
    run: str

    @property
    def id(self) -> str:
        """Stable identity of a test across runs (class + name)."""
        return f"{self.classname}.{self.name}" if self.classname else self.name


# Map the many ways formats spell a status onto our three canonical values.
_STATUS_ALIASES = {
    "passed": "passed", "pass": "passed", "ok": "passed", "success": "passed",
    "failed": "failed", "fail": "failed", "failure": "failed", "error": "failed",
    "skipped": "skipped", "skip": "skipped", "ignored": "skipped",
}


def _normalize_status(raw: str) -> str:
    """Return a canonical status or raise ValueError for unknown values."""
    key = str(raw).strip().lower()
    if key not in _STATUS_ALIASES:
        raise ValueError(f"unknown test status: {raw!r}")
    return _STATUS_ALIASES[key]


# --------------------------------------------------------------------------- #
# Parsers
# --------------------------------------------------------------------------- #

def parse_junit_xml(path: Path) -> list[TestCase]:
    """Parse a JUnit-style XML report into TestCase records.

    Handles both a top-level ``<testsuites>`` wrapper and a bare ``<testsuite>``.
    A ``<testcase>`` with a ``<failure>`` or ``<error>`` child is ``failed``; one
    with ``<skipped>`` is ``skipped``; otherwise ``passed``.
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"JUnit XML file not found: {path}")
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise ValueError(f"malformed JUnit XML in {path}: {exc}") from exc

    root = tree.getroot()
    # Collect every <testcase> wherever it lives in the tree.
    testcases = root.iter("testcase")
    run_id = path.stem
    results: list[TestCase] = []
    for tc in testcases:
        name = tc.get("name", "")
        classname = tc.get("classname", "")
        try:
            duration = float(tc.get("time", "0") or 0)
        except ValueError:
            duration = 0.0
        if tc.find("failure") is not None or tc.find("error") is not None:
            status = "failed"
        elif tc.find("skipped") is not None:
            status = "skipped"
        else:
            status = "passed"
        results.append(TestCase(classname, name, status, duration, run_id))
    return results


def parse_json(path: Path) -> list[TestCase]:
    """Parse a JSON report into TestCase records.

    Expected schema::

        {"tests": [{"name": ..., "classname": ..., "status": ..., "duration": ...}]}
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"JSON file not found: {path}")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"malformed JSON in {path}: {exc}") from exc

    tests = data.get("tests") if isinstance(data, dict) else None
    if not isinstance(tests, list):
        raise ValueError(f"JSON in {path} must contain a 'tests' array")

    run_id = path.stem
    results: list[TestCase] = []
    for entry in tests:
        if not isinstance(entry, dict) or "name" not in entry:
            raise ValueError(f"invalid test entry in {path}: {entry!r}")
        try:
            status = _normalize_status(entry.get("status", "passed"))
        except ValueError as exc:
            raise ValueError(f"{exc} (in {path})") from exc
        try:
            duration = float(entry.get("duration", 0) or 0)
        except (TypeError, ValueError):
            duration = 0.0
        results.append(TestCase(
            entry.get("classname", ""), entry["name"], status, duration, run_id))
    return results


def parse_file(path: Path) -> list[TestCase]:
    """Dispatch to the right parser based on file extension."""
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".xml":
        return parse_junit_xml(path)
    if suffix == ".json":
        return parse_json(path)
    raise ValueError(f"unsupported file type {suffix!r} for {path}; expected .xml or .json")


# --------------------------------------------------------------------------- #
# Aggregation
# --------------------------------------------------------------------------- #

def aggregate(cases: Iterable[TestCase]) -> dict:
    """Compute total / passed / failed / skipped / duration across all runs."""
    cases = list(cases)
    agg = {"total": len(cases), "passed": 0, "failed": 0, "skipped": 0, "duration": 0.0}
    for c in cases:
        agg[c.status] += 1
        agg["duration"] += c.duration
    return agg


def find_flaky(cases: Iterable[TestCase]) -> list[dict]:
    """Identify flaky tests: passed in >=1 run and failed in >=1 run.

    Skipped results are ignored -- a skip is neither a pass nor a fail and must
    not, on its own, make a test look flaky.
    """
    by_id: dict[str, set[str]] = {}
    for c in cases:
        if c.status == "skipped":
            continue
        by_id.setdefault(c.id, set()).add(c.status)
    flaky = []
    for test_id, statuses in sorted(by_id.items()):
        if "passed" in statuses and "failed" in statuses:
            flaky.append({"id": test_id})
    return flaky


# --------------------------------------------------------------------------- #
# Markdown rendering
# --------------------------------------------------------------------------- #

def generate_markdown(cases: Iterable[TestCase]) -> str:
    """Render a GitHub Actions job-summary markdown document."""
    cases = list(cases)
    agg = aggregate(cases)
    flaky = find_flaky(cases)
    runs = sorted({c.run for c in cases})

    lines = ["# Test Results Summary", ""]
    lines.append(f"Aggregated across **{len(runs)}** run(s): {', '.join(runs) or 'none'}")
    lines.append("")
    lines.append("| Total | Passed | Failed | Skipped | Duration (s) |")
    lines.append("| ----- | ------ | ------ | ------- | ------------ |")
    lines.append(
        f"| {agg['total']} | {agg['passed']} | {agg['failed']} | "
        f"{agg['skipped']} | {agg['duration']:.2f} |"
    )
    lines.append("")

    status_emoji = ":white_check_mark:" if agg["failed"] == 0 else ":x:"
    verdict = "All tests passed" if agg["failed"] == 0 else f"{agg['failed']} test(s) failed"
    lines.append(f"**Status:** {status_emoji} {verdict}")
    lines.append("")

    lines.append("## Flaky Tests")
    lines.append("")
    if flaky:
        lines.append("These tests passed in some runs and failed in others:")
        lines.append("")
        lines.append("| Test |")
        lines.append("| ---- |")
        for f in flaky:
            lines.append(f"| `{f['id']}` |")
    else:
        lines.append("No flaky tests detected.")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", help="JUnit XML and/or JSON result files")
    parser.add_argument("--output", "-o", help="write markdown here (default: stdout)")
    args = parser.parse_args(argv)

    all_cases: list[TestCase] = []
    for f in args.files:
        try:
            all_cases.extend(parse_file(Path(f)))
        except (FileNotFoundError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    md = generate_markdown(all_cases)

    if args.output:
        Path(args.output).write_text(md)
    else:
        print(md)

    # Also append to the GitHub Actions job summary when running in CI.
    import os
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a") as fh:
            fh.write(md + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
