"""Aggregate test results from multiple files and formats into a summary.

Supports two input formats:

* **JUnit XML** -- the de-facto standard emitted by most test runners
  (``<testsuites><testsuite><testcase .../></testsuite></testsuites>``).
* **JSON** -- a simple schema produced by custom tooling, e.g.::

      {"tests": [{"classname": "...", "name": "...",
                  "status": "passed", "duration": 0.1}]}

The module normalizes every test into a :class:`TestResult` keyed by
``classname::name`` so results can be compared across the multiple files of
a matrix build. It then computes totals and detects *flaky* tests -- those
that both passed and failed across the runs -- and renders a Markdown report
suitable for a GitHub Actions job summary.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field


# Canonical status vocabulary. Everything is normalized onto these values so
# the rest of the pipeline never has to special-case a runner's spelling.
PASSED = "passed"
FAILED = "failed"
SKIPPED = "skipped"


@dataclass
class TestResult:
    """One execution of one test case in one input file."""

    name: str  # fully-qualified "classname::name"
    status: str  # one of PASSED / FAILED / SKIPPED
    duration: float  # seconds


# Map every status spelling a runner might emit onto the canonical vocabulary.
_STATUS_ALIASES = {
    "passed": PASSED, "pass": PASSED, "ok": PASSED, "success": PASSED,
    "failed": FAILED, "fail": FAILED, "failure": FAILED, "error": FAILED,
    "skipped": SKIPPED, "skip": SKIPPED, "ignored": SKIPPED,
    "pending": SKIPPED, "disabled": SKIPPED,
}


def _normalize_status(raw: str) -> str:
    """Map a free-form status string onto PASSED/FAILED/SKIPPED."""
    key = (raw or "").strip().lower()
    if key not in _STATUS_ALIASES:
        raise ValueError(f"Unknown test status {raw!r}")
    return _STATUS_ALIASES[key]


def parse_junit_xml(path: str) -> list[TestResult]:
    """Parse a JUnit XML file into a list of :class:`TestResult`.

    Handles both a top-level ``<testsuites>`` wrapper and a bare
    ``<testsuite>`` root, which different runners emit. A ``<testcase>`` with
    a child ``<failure>`` or ``<error>`` counts as failed; a ``<skipped>``
    child counts as skipped; otherwise it passed.
    """
    try:
        tree = ET.parse(path)
    except (ET.ParseError, OSError) as exc:
        raise ValueError(f"Could not parse JUnit XML {path!r}: {exc}") from exc

    root = tree.getroot()
    # Normalize: collect every <testcase> regardless of nesting depth.
    testcases = root.iter("testcase")

    results: list[TestResult] = []
    for case in testcases:
        classname = case.get("classname", "")
        name = case.get("name", "")
        qualified = f"{classname}::{name}" if classname else name

        if case.find("failure") is not None or case.find("error") is not None:
            status = FAILED
        elif case.find("skipped") is not None:
            status = SKIPPED
        else:
            status = PASSED

        try:
            duration = float(case.get("time", "0") or 0)
        except ValueError:
            duration = 0.0

        results.append(TestResult(name=qualified, status=status, duration=duration))

    return results


# File extensions we know how to dispatch on, mapped to their parser.
_PARSERS = {
    ".xml": "parse_junit_xml",
    ".json": "parse_json",
}


@dataclass
class Aggregate:
    """Roll-up of every run, plus the data the Markdown report needs."""

    total: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    duration: float = 0.0
    file_count: int = 0
    flaky: list[str] = field(default_factory=list)
    # filename -> {"passed": n, "failed": n, "skipped": n, "duration": x}
    per_file: dict[str, dict] = field(default_factory=dict)


def aggregate(runs: dict[str, list[TestResult]]) -> Aggregate:
    """Combine per-file results into totals and detect flaky tests.

    *runs* maps filename -> results (as returned by :func:`parse_directory`).
    A test is **flaky** when, across the files, it recorded both a passed and
    a failed status -- the classic "green on retry" signature of a matrix
    build. Skipped statuses do not make a test flaky on their own.
    """
    agg = Aggregate(file_count=len(runs))

    # statuses seen per test name, used afterwards for flaky detection.
    statuses_by_test: dict[str, set[str]] = defaultdict(set)

    for filename, results in runs.items():
        counts = {PASSED: 0, FAILED: 0, SKIPPED: 0}
        file_duration = 0.0
        for r in results:
            agg.total += 1
            counts[r.status] += 1
            file_duration += r.duration
            agg.duration += r.duration
            statuses_by_test[r.name].add(r.status)

        agg.passed += counts[PASSED]
        agg.failed += counts[FAILED]
        agg.skipped += counts[SKIPPED]
        agg.per_file[filename] = {
            "passed": counts[PASSED],
            "failed": counts[FAILED],
            "skipped": counts[SKIPPED],
            "duration": file_duration,
        }

    # Flaky == both passed and failed observed for the same test. Sorted for
    # deterministic, reproducible report output.
    agg.flaky = sorted(
        name for name, seen in statuses_by_test.items()
        if PASSED in seen and FAILED in seen
    )

    return agg


def generate_markdown(agg: Aggregate) -> str:
    """Render an :class:`Aggregate` as a GitHub-flavored Markdown report.

    The layout is stable and exact-value friendly so CI can assert on it:
    a totals block, a per-file table, a flaky-test section, and an overall
    PASSED/FAILED verdict (FAILED iff any test failed).
    """
    verdict = "PASSED" if agg.failed == 0 else "FAILED"

    lines = [
        "# Test Results Summary",
        "",
        f"- **Total tests:** {agg.total}",
        f"- **Passed:** {agg.passed}",
        f"- **Failed:** {agg.failed}",
        f"- **Skipped:** {agg.skipped}",
        f"- **Total duration:** {agg.duration:.2f}s",
        f"- **Files aggregated:** {agg.file_count}",
        "",
        "## Per-file Breakdown",
        "",
        "| File | Passed | Failed | Skipped | Duration |",
        "| --- | --- | --- | --- | --- |",
    ]
    for filename in sorted(agg.per_file):
        f = agg.per_file[filename]
        lines.append(
            f"| {filename} | {f['passed']} | {f['failed']} | "
            f"{f['skipped']} | {f['duration']:.2f}s |"
        )

    lines += ["", "## Flaky Tests", ""]
    if agg.flaky:
        lines.append(
            f"These tests passed in some runs and failed in others "
            f"({len(agg.flaky)}):"
        )
        lines += [f"- `{name}`" for name in agg.flaky]
    else:
        lines.append("No flaky tests detected.")

    lines += ["", f"**Overall result:** {verdict}", ""]
    return "\n".join(lines)


def parse_file(path: str) -> list[TestResult]:
    """Parse a single result file, dispatching on its extension."""
    ext = os.path.splitext(path)[1].lower()
    parser_name = _PARSERS.get(ext)
    if parser_name is None:
        supported = ", ".join(sorted(_PARSERS))
        raise ValueError(
            f"Unsupported file type {ext!r} for {path!r} (supported: {supported})"
        )
    return globals()[parser_name](path)


def parse_directory(directory: str) -> dict[str, list[TestResult]]:
    """Parse every supported result file in *directory*.

    Returns a mapping of filename -> that file's results. Each file models
    one leg of a matrix build, which is exactly the granularity flaky-test
    detection needs (a test is flaky if its status differs across files).
    """
    paths = sorted(
        p for p in glob.glob(os.path.join(directory, "*"))
        if os.path.splitext(p)[1].lower() in _PARSERS and os.path.isfile(p)
    )
    if not paths:
        raise ValueError(f"No test result files found in {directory!r}")

    return {os.path.basename(p): parse_file(p) for p in paths}


def parse_json(path: str) -> list[TestResult]:
    """Parse a JSON test-result file into a list of :class:`TestResult`.

    Expected schema: a top-level object with a ``"tests"`` array, each item
    carrying ``name`` (and optional ``classname``), ``status`` and
    ``duration``. Status strings are normalized via :data:`_STATUS_ALIASES`.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        raise ValueError(f"Could not parse JSON {path!r}: {exc}") from exc

    tests = data.get("tests")
    if not isinstance(tests, list):
        raise ValueError(f"JSON {path!r} must have a top-level 'tests' array")

    results: list[TestResult] = []
    for item in tests:
        classname = item.get("classname", "")
        name = item.get("name", "")
        qualified = f"{classname}::{name}" if classname else name
        status = _normalize_status(item.get("status", ""))
        try:
            duration = float(item.get("duration", 0) or 0)
        except (TypeError, ValueError):
            duration = 0.0
        results.append(TestResult(name=qualified, status=status, duration=duration))

    return results


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: aggregate a directory of result files into Markdown.

    Prints the report to stdout and, when ``--summary-file`` (or the
    ``GITHUB_STEP_SUMMARY`` env var) is set, appends it there too so it shows
    up as a GitHub Actions job summary. Returns a process exit code:

    * ``0`` on success (even if aggregated tests failed -- aggregation itself
      succeeded), unless ``--fail-on-failure`` is given and a test failed,
    * ``1`` when ``--fail-on-failure`` is set and at least one test failed,
    * ``2`` on an aggregation error (bad input, missing directory, ...).
    """
    parser = argparse.ArgumentParser(
        description="Aggregate JUnit XML / JSON test results into a Markdown summary."
    )
    parser.add_argument("directory", help="Directory containing result files.")
    parser.add_argument(
        "--summary-file",
        default=os.environ.get("GITHUB_STEP_SUMMARY"),
        help="File to append the Markdown report to (default: $GITHUB_STEP_SUMMARY).",
    )
    parser.add_argument(
        "--fail-on-failure",
        action="store_true",
        help="Exit non-zero if any aggregated test failed.",
    )
    args = parser.parse_args(argv)

    try:
        runs = parse_directory(args.directory)
        agg = aggregate(runs)
        report = generate_markdown(agg)
    except ValueError as exc:
        # Graceful, meaningful error -- no traceback dumped on the user.
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(report)

    if args.summary_file:
        try:
            with open(args.summary_file, "a", encoding="utf-8") as fh:
                fh.write(report + "\n")
        except OSError as exc:
            print(f"Error: could not write summary file: {exc}", file=sys.stderr)
            return 2

    if args.fail_on_failure and agg.failed > 0:
        return 1
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
