"""
Test Results Aggregator.

Parses test result files in JUnit XML and JSON formats, aggregates results
across multiple files (e.g. from a CI matrix build), computes totals, detects
flaky tests (same test name passing in some runs and failing in others), and
renders a Markdown summary suitable for a GitHub Actions job summary
(GITHUB_STEP_SUMMARY).
"""
from __future__ import annotations

import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Iterable


VALID_STATUSES = {"passed", "failed", "skipped"}


class AggregatorError(Exception):
    """Raised for any recoverable error while parsing or aggregating results."""


@dataclass(frozen=True)
class CaseResult:
    """A single test case result, normalized across input formats."""

    name: str
    classname: str
    status: str  # one of "passed", "failed", "skipped"
    time: float = 0.0
    message: str = ""
    source_file: str = ""

    def __post_init__(self):
        if self.status not in VALID_STATUSES:
            raise AggregatorError(
                f"Invalid test status {self.status!r} for test "
                f"{self.classname}.{self.name} (must be one of {sorted(VALID_STATUSES)})"
            )


@dataclass
class FileResult:
    """All test cases parsed from one result file, tagged with the source path."""

    path: str
    label: str
    cases: list = field(default_factory=list)


def parse_junit_xml(path: str) -> list:
    """Parse a JUnit XML file into a list of CaseResult objects.

    Supports both a bare <testsuite> root and a <testsuites> wrapper
    containing multiple <testsuite> children.
    """
    if not os.path.isfile(path):
        raise AggregatorError(f"JUnit XML file not found: {path}")

    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise AggregatorError(f"Failed to parse JUnit XML file {path}: {exc}") from exc

    root = tree.getroot()
    suites = [root] if root.tag == "testsuite" else list(root.findall("testsuite"))
    if not suites:
        raise AggregatorError(f"No <testsuite> elements found in {path}")

    cases = []
    for suite in suites:
        for testcase_el in suite.findall("testcase"):
            name = testcase_el.get("name")
            classname = testcase_el.get("classname", "")
            time_attr = testcase_el.get("time", "0")
            try:
                time_val = float(time_attr)
            except ValueError:
                time_val = 0.0

            if name is None:
                raise AggregatorError(f"<testcase> missing required 'name' attribute in {path}")

            status = "passed"
            message = ""
            failure_el = testcase_el.find("failure")
            error_el = testcase_el.find("error")
            skipped_el = testcase_el.find("skipped")
            if failure_el is not None:
                status = "failed"
                message = failure_el.get("message", "")
            elif error_el is not None:
                status = "failed"
                message = error_el.get("message", "")
            elif skipped_el is not None:
                status = "skipped"
                message = skipped_el.get("message", "")

            cases.append(
                CaseResult(
                    name=name,
                    classname=classname,
                    status=status,
                    time=time_val,
                    message=message,
                    source_file=path,
                )
            )
    return cases


def parse_json_results(path: str) -> list:
    """Parse a JSON test result file into a list of CaseResult objects.

    Expected schema:
        {"tests": [{"name": str, "classname": str (optional),
                     "status": "passed"|"failed"|"skipped",
                     "time": float (optional), "message": str (optional)}, ...]}
    """
    if not os.path.isfile(path):
        raise AggregatorError(f"JSON results file not found: {path}")

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AggregatorError(f"Failed to parse JSON results file {path}: {exc}") from exc

    if not isinstance(data, dict) or "tests" not in data:
        raise AggregatorError(
            f"JSON results file {path} must be an object with a 'tests' array"
        )

    cases = []
    for i, entry in enumerate(data["tests"]):
        if "name" not in entry:
            raise AggregatorError(f"Test entry #{i} in {path} is missing required 'name' field")
        if "status" not in entry:
            raise AggregatorError(f"Test entry #{i} in {path} is missing required 'status' field")
        try:
            cases.append(
                CaseResult(
                    name=entry["name"],
                    classname=entry.get("classname", ""),
                    status=entry["status"],
                    time=float(entry.get("time", 0.0)),
                    message=entry.get("message", ""),
                    source_file=path,
                )
            )
        except AggregatorError:
            raise
    return cases


def parse_file(path: str) -> list:
    """Dispatch to the correct parser based on file extension."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".xml":
        return parse_junit_xml(path)
    if ext == ".json":
        return parse_json_results(path)
    raise AggregatorError(f"Unsupported test result file extension {ext!r} for {path}")


def _test_key(case: CaseResult) -> str:
    """Unique identifier for a test, used to detect the same test across runs."""
    return f"{case.classname}::{case.name}" if case.classname else case.name


def aggregate(paths: Iterable[str], labels: dict = None) -> dict:
    """Aggregate test results across multiple files.

    `labels` optionally maps a file path to a human-readable run label
    (e.g. "ubuntu-latest / py3.12"); defaults to the basename of the file.

    Returns a summary dict with:
        - files: list of FileResult
        - totals: {"passed": int, "failed": int, "skipped": int, "total": int, "duration": float}
        - flaky: list of dicts {"key": str, "name": str, "classname": str,
                                  "statuses": {label: status}}
    """
    labels = labels or {}
    paths = list(paths)
    if not paths:
        raise AggregatorError("No test result files provided to aggregate")

    file_results = []
    totals = {"passed": 0, "failed": 0, "skipped": 0, "total": 0, "duration": 0.0}
    # key -> {label: status}
    by_test: dict = {}
    # key -> (name, classname)
    test_identity: dict = {}

    for path in paths:
        cases = parse_file(path)
        label = labels.get(path, os.path.basename(path))
        file_results.append(FileResult(path=path, label=label, cases=cases))

        for case in cases:
            totals[case.status] += 1
            totals["total"] += 1
            totals["duration"] += case.time

            key = _test_key(case)
            test_identity[key] = (case.name, case.classname)
            by_test.setdefault(key, {})[label] = case.status

    flaky = []
    for key, statuses in by_test.items():
        distinct = set(statuses.values())
        # Flaky = mix of pass and fail across runs (skipped alone doesn't count as flaky).
        if "passed" in distinct and "failed" in distinct:
            name, classname = test_identity[key]
            flaky.append(
                {
                    "key": key,
                    "name": name,
                    "classname": classname,
                    "statuses": statuses,
                }
            )

    flaky.sort(key=lambda f: f["key"])

    return {
        "files": file_results,
        "totals": totals,
        "flaky": flaky,
    }


def render_markdown(summary: dict, title: str = "Test Results Summary") -> str:
    """Render an aggregated summary dict as a GitHub Actions job-summary-friendly Markdown string."""
    totals = summary["totals"]
    files = summary["files"]
    flaky = summary["flaky"]

    lines = [f"# {title}", ""]

    overall_icon = "✅" if totals["failed"] == 0 else "❌"
    lines.append(f"{overall_icon} **{totals['total']} tests** across {len(files)} run(s) "
                 f"in {totals['duration']:.2f}s")
    lines.append("")
    lines.append("| Passed | Failed | Skipped | Total | Duration |")
    lines.append("|---|---|---|---|---|")
    lines.append(
        f"| {totals['passed']} ✅ | {totals['failed']} ❌ | {totals['skipped']} ⏭️ "
        f"| {totals['total']} | {totals['duration']:.2f}s |"
    )
    lines.append("")

    lines.append("## Results by Run")
    lines.append("")
    lines.append("| Run | Passed | Failed | Skipped | Duration |")
    lines.append("|---|---|---|---|---|")
    for fr in files:
        p = sum(1 for c in fr.cases if c.status == "passed")
        f_ = sum(1 for c in fr.cases if c.status == "failed")
        s = sum(1 for c in fr.cases if c.status == "skipped")
        d = sum(c.time for c in fr.cases)
        lines.append(f"| {fr.label} | {p} | {f_} | {s} | {d:.2f}s |")
    lines.append("")

    lines.append("## Flaky Tests")
    lines.append("")
    if not flaky:
        lines.append("No flaky tests detected. 🎉")
    else:
        lines.append("The following tests had inconsistent results across runs:")
        lines.append("")
        lines.append("| Test | Results |")
        lines.append("|---|---|")
        for f in flaky:
            display_name = f"{f['classname']}.{f['name']}" if f["classname"] else f["name"]
            statuses_str = ", ".join(
                f"{label}: {'✅' if s == 'passed' else '❌' if s == 'failed' else '⏭️'}"
                for label, s in f["statuses"].items()
            )
            lines.append(f"| `{display_name}` | {statuses_str} |")
    lines.append("")

    return "\n".join(lines)


def main(argv=None) -> int:
    """CLI entry point: aggregate the given result files and write Markdown
    to stdout and (if set) to $GITHUB_STEP_SUMMARY."""
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        print("Usage: aggregator.py <result-file> [<result-file> ...]", file=sys.stderr)
        return 2

    try:
        summary = aggregate(argv)
        markdown = render_markdown(summary)
    except AggregatorError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(markdown)

    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        with open(step_summary_path, "a", encoding="utf-8") as f:
            f.write(markdown)
            f.write("\n")

    return 1 if summary["totals"]["failed"] > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
