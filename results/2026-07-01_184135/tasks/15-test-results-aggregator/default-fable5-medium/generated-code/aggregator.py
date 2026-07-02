"""Test results aggregator.

Parses test result files (JUnit XML and JSON), aggregates results across
multiple files (as produced by a CI matrix build), computes totals, detects
flaky tests (passed in one run, failed in another), and renders a markdown
summary suitable for a GitHub Actions job summary.

Design: every parser normalizes its input into a list of TestResult records.
Everything downstream (totals, flaky detection, markdown) works only on that
uniform shape, so new input formats only require a new parser function.
"""
from __future__ import annotations

import json
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

VALID_STATUSES = ("passed", "failed", "skipped")


class AggregatorError(Exception):
    """Raised for any user-facing input problem (bad file, bad format)."""


@dataclass(frozen=True)
class TestResult:
    classname: str
    name: str
    status: str  # "passed" | "failed" | "skipped"
    duration: float  # seconds

    @property
    def full_name(self) -> str:
        """Identity used to correlate the same test across matrix runs."""
        return f"{self.classname}::{self.name}" if self.classname else self.name


def parse_junit_xml(path: str | Path) -> list[TestResult]:
    """Parse a JUnit XML file into TestResult records.

    Supports both a bare <testsuite> root and a <testsuites> wrapper.
    <error> elements are treated as failures; <skipped> as skipped.
    """
    path = Path(path)
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        raise AggregatorError(f"{path}: not valid XML: {exc}") from exc

    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")
    results: list[TestResult] = []
    for suite in suites:
        for case in suite.findall("testcase"):
            if case.find("skipped") is not None:
                status = "skipped"
            elif case.find("failure") is not None or case.find("error") is not None:
                status = "failed"
            else:
                status = "passed"
            results.append(TestResult(
                classname=case.get("classname", ""),
                name=case.get("name", ""),
                status=status,
                duration=float(case.get("time") or 0.0),
            ))
    return results


def parse_json(path: str | Path) -> list[TestResult]:
    """Parse a JSON results file: {"tests": [{name, status, classname?, duration?}]}."""
    path = Path(path)
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise AggregatorError(f"{path}: not valid JSON: {exc}") from exc

    tests = data.get("tests") if isinstance(data, dict) else None
    if not isinstance(tests, list):
        raise AggregatorError(f"{path}: missing a 'tests' list at the top level")

    results: list[TestResult] = []
    for entry in tests:
        status = entry.get("status")
        if status not in VALID_STATUSES:
            raise AggregatorError(
                f"{path}: invalid status {status!r} for test {entry.get('name')!r} "
                f"(expected one of {', '.join(VALID_STATUSES)})")
        results.append(TestResult(
            classname=entry.get("classname", ""),
            name=entry.get("name", ""),
            status=status,
            duration=float(entry.get("duration", 0.0)),
        ))
    return results


def parse_file(path: str | Path) -> list[TestResult]:
    """Dispatch to the right parser based on the file extension."""
    path = Path(path)
    if not path.exists():
        raise AggregatorError(f"{path}: file does not exist")
    if path.suffix == ".xml":
        return parse_junit_xml(path)
    if path.suffix == ".json":
        return parse_json(path)
    raise AggregatorError(
        f"{path}: unsupported file type {path.suffix!r} (expected .xml or .json)")


@dataclass(frozen=True)
class FlakyTest:
    """A test that both passed and failed across the aggregated runs."""
    full_name: str
    passes: int
    failures: int


@dataclass(frozen=True)
class Summary:
    total: int
    passed: int
    failed: int
    skipped: int
    duration: float
    flaky: list[FlakyTest]


def aggregate(runs: list[list[TestResult]]) -> Summary:
    """Aggregate result lists from multiple runs (matrix jobs) into a Summary.

    Totals count every executed test case (the same test in N runs counts N
    times, matching what actually ran in CI). Flaky detection correlates by
    full_name: a test is flaky iff it has >=1 pass and >=1 failure.
    """
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    duration = 0.0
    outcomes: dict[str, dict[str, int]] = {}
    for run in runs:
        for r in run:
            counts[r.status] += 1
            duration += r.duration
            per_test = outcomes.setdefault(r.full_name, {"passed": 0, "failed": 0})
            if r.status in per_test:
                per_test[r.status] += 1

    flaky = [
        FlakyTest(name, o["passed"], o["failed"])
        for name, o in sorted(outcomes.items())
        if o["passed"] and o["failed"]
    ]
    return Summary(
        total=sum(counts.values()),
        passed=counts["passed"],
        failed=counts["failed"],
        skipped=counts["skipped"],
        duration=duration,
        flaky=flaky,
    )


def generate_markdown(summary: Summary) -> str:
    """Render a Summary as markdown for $GITHUB_STEP_SUMMARY."""
    status = "❌ FAILING" if summary.failed else "✅ PASSING"
    lines = [
        "# Test Results Summary",
        "",
        f"**Status:** {status}",
        "",
        "| Metric | Value |",
        "| --- | --- |",
        f"| ✅ Passed | {summary.passed} |",
        f"| ❌ Failed | {summary.failed} |",
        f"| ⏭️ Skipped | {summary.skipped} |",
        f"| Σ Total | {summary.total} |",
        f"| ⏱️ Duration | {summary.duration:.2f}s |",
        "",
        "## ⚠️ Flaky tests",
        "",
    ]
    if summary.flaky:
        lines += ["| Test | Passed | Failed |", "| --- | --- | --- |"]
        lines += [f"| `{f.full_name}` | {f.passes} | {f.failures} |" for f in summary.flaky]
    else:
        lines.append("No flaky tests detected. 🎉")
    return "\n".join(lines) + "\n"


def collect_result_files(target: str | Path) -> list[Path]:
    """Resolve a directory (or single file) into a sorted list of result files."""
    target = Path(target)
    if target.is_dir():
        files = sorted(p for p in target.iterdir() if p.suffix in (".xml", ".json"))
        if not files:
            raise AggregatorError(
                f"{target}: no result files (*.xml, *.json) found in directory")
        return files
    return [target]


def main(argv: list[str] | None = None) -> int:
    """CLI: aggregate result files and emit the markdown summary.

    Prints machine-readable TOTALS/FLAKY lines to stdout for CI assertions,
    writes markdown to --output, and appends it to $GITHUB_STEP_SUMMARY when
    running under GitHub Actions.
    """
    import argparse
    import os
    import sys

    parser = argparse.ArgumentParser(
        description="Aggregate JUnit XML / JSON test results into a markdown summary.")
    parser.add_argument("inputs", nargs="+",
                        help="result files or directories containing them")
    parser.add_argument("--output", help="write the markdown summary to this file")
    args = parser.parse_args(argv)

    try:
        files = [f for target in args.inputs for f in collect_result_files(target)]
        runs = [parse_file(f) for f in files]  # each file == one matrix run
    except AggregatorError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    summary = aggregate(runs)
    print(f"Aggregated {len(files)} result file(s): "
          + ", ".join(f.name for f in files))
    print(f"TOTALS passed={summary.passed} failed={summary.failed} "
          f"skipped={summary.skipped} total={summary.total} "
          f"duration={summary.duration:.2f}")
    if summary.flaky:
        for f in summary.flaky:
            print(f"FLAKY {f.full_name} passes={f.passes} failures={f.failures}")
    else:
        print("FLAKY none")

    markdown = generate_markdown(summary)
    if args.output:
        Path(args.output).write_text(markdown)
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a") as fh:
            fh.write(markdown)
    if not args.output and not step_summary:
        print(markdown)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
