#!/usr/bin/env python3
"""Test-results aggregator for matrix builds.

Parses test result files in two formats:

* JUnit XML  (``*.xml``)  — the de-facto CI standard (`<testsuites>`/`<testsuite>`
  roots with `<testcase>` children carrying `<failure>`, `<error>` or
  `<skipped>` markers).
* JSON       (``*.json``) — a simple schema:
      {"suite": "name", "tests": [
          {"name": "...", "classname": "...", "status": "passed|failed|skipped",
           "duration": 1.23, "message": "optional"}]}

Each input file represents one leg of a matrix build. The aggregator:

1. parses every file in a directory (or an explicit file list),
2. computes totals (passed / failed / skipped / duration),
3. flags *flaky* tests — tests that passed in at least one run and failed in
   at least one other,
4. emits a markdown summary suitable for ``$GITHUB_STEP_SUMMARY``.

Only the Python standard library is used, so it runs in any CI container.
Developed test-first; see tests/test_aggregator.py for the TDD cycles.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path


class AggregatorError(Exception):
    """Raised for any user-facing input problem (bad file, bad format...).

    The CLI catches this and prints the message to stderr with exit code 1,
    so callers always get a meaningful error instead of a traceback.
    """


# Statuses every parser normalizes to. JUnit <error> is treated as "failed"
# because for aggregation purposes an errored test is a non-passing run.
VALID_STATUSES = ("passed", "failed", "skipped")


@dataclass
class TestResult:
    """Outcome of a single test case within a single run (file)."""

    name: str
    classname: str = ""
    status: str = "passed"
    duration: float = 0.0
    message: str = ""

    @property
    def test_id(self) -> str:
        """Stable identity used to match the same test across matrix runs."""
        return f"{self.classname}::{self.name}" if self.classname else self.name


def _parse_time(value: str | None, context: str) -> float:
    """Parse a duration attribute, tolerating missing values."""
    if value is None or value == "":
        return 0.0
    try:
        return float(value)
    except ValueError:
        raise AggregatorError(f"{context}: invalid duration value {value!r}")


def parse_junit_xml(path: Path | str) -> list[TestResult]:
    """Parse one JUnit XML report file into a list of TestResult records."""
    path = Path(path)
    try:
        tree = ET.parse(path)
    except FileNotFoundError:
        raise AggregatorError(f"{path}: file not found")
    except ET.ParseError as exc:
        raise AggregatorError(f"{path}: not valid XML ({exc})")

    root = tree.getroot()
    # Accept either a <testsuites> wrapper or a bare <testsuite> root.
    if root.tag == "testsuite":
        suites = [root]
    elif root.tag == "testsuites":
        suites = list(root.iter("testsuite"))
    else:
        raise AggregatorError(
            f"{path}: unexpected root element <{root.tag}> "
            "(expected <testsuite> or <testsuites>)"
        )

    results: list[TestResult] = []
    for suite in suites:
        for case in suite.iter("testcase"):
            name = case.get("name")
            if not name:
                raise AggregatorError(f"{path}: <testcase> is missing a 'name' attribute")
            status, message = "passed", ""
            # Child elements decide the outcome; <error> counts as failed.
            for child_tag, mapped in (("failure", "failed"),
                                      ("error", "failed"),
                                      ("skipped", "skipped")):
                child = case.find(child_tag)
                if child is not None:
                    status = mapped
                    message = child.get("message") or (child.text or "").strip()
                    break
            results.append(TestResult(
                name=name,
                classname=case.get("classname", ""),
                status=status,
                duration=_parse_time(case.get("time"), f"{path}: testcase {name!r}"),
                message=message,
            ))
    return results


def parse_json_results(path: Path | str) -> list[TestResult]:
    """Parse one JSON results file (see module docstring for the schema)."""
    import json

    path = Path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise AggregatorError(f"{path}: file not found")
    except json.JSONDecodeError as exc:
        raise AggregatorError(f"{path}: not valid JSON ({exc})")

    if not isinstance(data, dict) or not isinstance(data.get("tests"), list):
        raise AggregatorError(f"{path}: expected a JSON object with a 'tests' array")

    results: list[TestResult] = []
    for i, entry in enumerate(data["tests"]):
        if not isinstance(entry, dict) or "name" not in entry:
            raise AggregatorError(f"{path}: tests[{i}] must be an object with a 'name' field")
        status = entry.get("status", "passed")
        if status not in VALID_STATUSES:
            raise AggregatorError(
                f"{path}: tests[{i}] has unknown status {status!r} "
                f"(expected one of {', '.join(VALID_STATUSES)})"
            )
        duration = entry.get("duration", 0.0)
        if not isinstance(duration, (int, float)):
            raise AggregatorError(f"{path}: tests[{i}] duration must be a number")
        results.append(TestResult(
            name=str(entry["name"]),
            classname=str(entry.get("classname", "")),
            status=status,
            duration=float(duration),
            message=str(entry.get("message", "") or ""),
        ))
    return results


@dataclass
class RunResult:
    """All test results from one file, i.e. one leg of the matrix build."""

    source: str                       # file name the run was parsed from
    tests: list[TestResult] = field(default_factory=list)

    def count(self, status: str) -> int:
        return sum(1 for t in self.tests if t.status == status)

    @property
    def duration(self) -> float:
        return sum(t.duration for t in self.tests)


@dataclass
class FlakyTest:
    """A test that passed in some runs and failed in others."""

    test_id: str
    passed_in: list[str]              # source files where it passed
    failed_in: list[str]              # source files where it failed


@dataclass
class Summary:
    """Aggregated view over all runs of a matrix build."""

    runs: list[RunResult]
    passed: int
    failed: int
    skipped: int
    duration: float
    flaky: list[FlakyTest]

    @property
    def total(self) -> int:
        return self.passed + self.failed + self.skipped


# Dispatch table: file extension -> parser. Extending to a new format only
# requires adding a parser function and one entry here.
PARSERS = {
    ".xml": parse_junit_xml,
    ".json": parse_json_results,
}


def load_results_file(path: Path | str) -> RunResult:
    """Parse a single result file, choosing the parser by file extension."""
    path = Path(path)
    parser = PARSERS.get(path.suffix.lower())
    if parser is None:
        raise AggregatorError(
            f"{path}: unsupported file type {path.suffix!r} "
            f"(supported: {', '.join(sorted(PARSERS))})"
        )
    return RunResult(source=path.name, tests=parser(path))


def aggregate_runs(runs: list[RunResult]) -> Summary:
    """Compute totals and flaky tests across the given runs.

    A test is *flaky* when the same test id passed in at least one run and
    failed in at least one other. Consistent failures are not flaky.
    """
    outcomes: dict[str, dict[str, list[str]]] = {}
    for run in runs:
        for t in run.tests:
            outcomes.setdefault(t.test_id, {"passed": [], "failed": []})
            if t.status in ("passed", "failed"):
                outcomes[t.test_id][t.status].append(run.source)

    flaky = [
        FlakyTest(test_id, o["passed"], o["failed"])
        for test_id, o in sorted(outcomes.items())
        if o["passed"] and o["failed"]
    ]
    return Summary(
        runs=runs,
        passed=sum(r.count("passed") for r in runs),
        failed=sum(r.count("failed") for r in runs),
        skipped=sum(r.count("skipped") for r in runs),
        duration=sum(r.duration for r in runs),
        flaky=flaky,
    )


def aggregate_directory(directory: Path | str) -> Summary:
    """Parse every supported result file in *directory* and aggregate them."""
    directory = Path(directory)
    if not directory.is_dir():
        raise AggregatorError(f"{directory}: no such directory")
    files = sorted(
        p for p in directory.iterdir()
        if p.is_file() and p.suffix.lower() in PARSERS
    )
    if not files:
        raise AggregatorError(
            f"{directory}: no test result files found "
            f"(looked for {', '.join(sorted(PARSERS))})"
        )
    return aggregate_runs([load_results_file(p) for p in files])


def render_markdown(summary: Summary) -> str:
    """Render the aggregated summary as GitHub-flavored markdown.

    The output is designed to be appended to ``$GITHUB_STEP_SUMMARY``.
    """
    lines = [
        "# 🧪 Test Results Summary",
        "",
        f"Aggregated **{len(summary.runs)}** result file(s) from the matrix build.",
        "",
        "| Metric | Count |",
        "| --- | --- |",
        f"| ✅ Passed | {summary.passed} |",
        f"| ❌ Failed | {summary.failed} |",
        f"| ⏭️ Skipped | {summary.skipped} |",
        f"| **Total** | **{summary.total}** |",
        "",
        f"**Total duration:** {summary.duration:.2f}s",
        "",
    ]

    if summary.flaky:
        lines += [
            f"## ⚠️ Flaky tests ({len(summary.flaky)})",
            "",
            "Tests that passed in some runs but failed in others:",
            "",
            "| Test | Passed in | Failed in |",
            "| --- | --- | --- |",
        ]
        lines += [
            f"| `{f.test_id}` | {', '.join(sorted(f.passed_in))} "
            f"| {', '.join(sorted(f.failed_in))} |"
            for f in summary.flaky
        ]
        lines.append("")
    else:
        lines += ["## ✅ No flaky tests detected", ""]

    lines += [
        "## Per-run breakdown",
        "",
        "| Run (file) | Passed | Failed | Skipped | Duration |",
        "| --- | --- | --- | --- | --- |",
    ]
    lines += [
        f"| {r.source} | {r.count('passed')} | {r.count('failed')} "
        f"| {r.count('skipped')} | {r.duration:.2f}s |"
        for r in summary.runs
    ]
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code (0 = success).

    stdout carries stable machine-readable lines (``RESULT ...`` and
    ``FLAKY ...``) so CI pipelines can assert on exact values; the markdown
    summary is written to ``--output`` (default: summary.md).
    """
    import argparse

    parser = argparse.ArgumentParser(
        prog="aggregator",
        description="Aggregate JUnit XML / JSON test results from a matrix build.",
    )
    parser.add_argument("directory", help="directory containing *.xml / *.json result files")
    parser.add_argument("--output", default="summary.md",
                        help="where to write the markdown summary (default: %(default)s)")
    args = parser.parse_args(argv)

    import sys

    try:
        summary = aggregate_directory(args.directory)
    except AggregatorError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    Path(args.output).write_text(render_markdown(summary), encoding="utf-8")

    # Machine-readable lines for CI assertions.
    print(
        f"RESULT total={summary.total} passed={summary.passed} "
        f"failed={summary.failed} skipped={summary.skipped} "
        f"duration={summary.duration:.2f} flaky={len(summary.flaky)}"
    )
    for f in summary.flaky:
        print(f"FLAKY {f.test_id}")
    print(f"Markdown summary written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
