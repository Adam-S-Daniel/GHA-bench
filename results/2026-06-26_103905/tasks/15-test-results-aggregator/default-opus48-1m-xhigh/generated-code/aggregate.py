#!/usr/bin/env python3
"""Aggregate test results from multiple files and formats into a summary.

This is the implementation for "Task 15: Test Results Aggregator". It:

  * parses test result files in two formats -- JUnit XML and a simple JSON shape,
  * aggregates many files together (one file == one leg of a matrix build),
  * computes totals (passed / failed / errors / skipped / duration),
  * identifies flaky tests (a test that passed in some legs and failed in others),
  * renders a Markdown summary suitable for ``$GITHUB_STEP_SUMMARY``.

Only the Python standard library is used so the script runs unchanged in a bare
GitHub Actions / act container with no ``pip install`` step.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from xml.etree import ElementTree as ET

# Canonical statuses. Everything a parser reads is normalised to one of these.
PASSED = "passed"
FAILED = "failed"
ERROR = "error"
SKIPPED = "skipped"


@dataclass(frozen=True)
class TestCaseResult:
    """A single test execution within one result file (one matrix leg)."""

    name: str          # stable identity, e.g. "auth.LoginTests.test_login"
    status: str        # one of PASSED / FAILED / ERROR / SKIPPED
    duration: float    # seconds
    file: str = ""     # source file name, for the per-file breakdown


@dataclass
class RunResult:
    """All test cases parsed from a single result file."""

    file: str
    cases: list[TestCaseResult] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return sum(c.duration for c in self.cases)

    def count(self, status: str) -> int:
        return sum(1 for c in self.cases if c.status == status)


class AggregateError(Exception):
    """Raised with a human-readable message when input cannot be processed."""


# ---------------------------------------------------------------------------
# JUnit XML parsing
# ---------------------------------------------------------------------------
def _classify_junit_testcase(testcase: ET.Element) -> str:
    """Map a <testcase> element to a canonical status.

    JUnit encodes the outcome as a child element: <failure>, <error> or
    <skipped>. A testcase with none of those passed.
    """
    if testcase.find("error") is not None:
        return ERROR
    if testcase.find("failure") is not None:
        return FAILED
    if testcase.find("skipped") is not None:
        return SKIPPED
    return PASSED


def parse_junit_xml(path: Path) -> RunResult:
    """Parse a JUnit XML file (``<testsuites>`` or a bare ``<testsuite>``)."""
    path = Path(path)
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise AggregateError(f"{path.name}: malformed JUnit XML ({exc})") from exc

    root = tree.getroot()
    # Accept either a <testsuites> wrapper or a single top-level <testsuite>.
    suites = root.iter("testsuite")
    run = RunResult(file=path.name)
    for suite in suites:
        for testcase in suite.findall("testcase"):
            name = testcase.get("name", "")
            classname = testcase.get("classname", "")
            full_name = f"{classname}.{name}" if classname else name
            try:
                duration = float(testcase.get("time", "0") or 0)
            except ValueError:
                duration = 0.0
            run.cases.append(
                TestCaseResult(
                    name=full_name,
                    status=_classify_junit_testcase(testcase),
                    duration=duration,
                    file=path.name,
                )
            )
    return run


# ---------------------------------------------------------------------------
# JSON parsing
# ---------------------------------------------------------------------------
# Normalise common status spellings to our canonical set.
_STATUS_ALIASES = {
    "passed": PASSED, "pass": PASSED, "ok": PASSED, "success": PASSED,
    "failed": FAILED, "fail": FAILED, "failure": FAILED,
    "error": ERROR, "errored": ERROR,
    "skipped": SKIPPED, "skip": SKIPPED, "ignored": SKIPPED,
}


def _normalise_status(raw: str, *, where: str) -> str:
    status = _STATUS_ALIASES.get(str(raw).strip().lower())
    if status is None:
        raise AggregateError(f"{where}: unknown test status '{raw}'")
    return status


def parse_json_results(path: Path) -> RunResult:
    """Parse a JSON results file.

    Accepts either an object with a ``tests`` array or a bare array of tests.
    Each test is ``{"name", "status", "duration"|"time"}``.
    """
    path = Path(path)
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise AggregateError(f"{path.name}: malformed JSON ({exc})") from exc

    if isinstance(data, dict):
        tests = data.get("tests")
    elif isinstance(data, list):
        tests = data
    else:
        tests = None
    if not isinstance(tests, list):
        raise AggregateError(
            f"{path.name}: expected a JSON array of tests or an object with a "
            f"'tests' array"
        )

    run = RunResult(file=path.name)
    for i, t in enumerate(tests):
        if not isinstance(t, dict) or "name" not in t or "status" not in t:
            raise AggregateError(
                f"{path.name}: test #{i} must be an object with 'name' and 'status'"
            )
        raw_duration = t.get("duration", t.get("time", 0))
        try:
            duration = float(raw_duration)
        except (TypeError, ValueError):
            duration = 0.0
        run.cases.append(
            TestCaseResult(
                name=str(t["name"]),
                status=_normalise_status(t["status"], where=f"{path.name} test #{i}"),
                duration=duration,
                file=path.name,
            )
        )
    return run


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
def parse_result_file(path: Path) -> RunResult:
    """Parse a single result file, choosing the parser by extension."""
    path = Path(path)
    if not path.exists():
        raise AggregateError(f"{path}: file not found")
    suffix = path.suffix.lower()
    if suffix == ".xml":
        return parse_junit_xml(path)
    if suffix == ".json":
        return parse_json_results(path)
    raise AggregateError(
        f"{path.name}: unsupported file type '{suffix}' (expected .xml or .json)"
    )


def collect_result_files(paths: list[Path]) -> list[Path]:
    """Expand the given paths into a sorted list of result files.

    A path may be an individual ``.xml``/``.json`` file or a directory, which is
    scanned (non-recursively) for those extensions. Sorting makes the aggregated
    output deterministic regardless of filesystem ordering.
    """
    found: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if not p.exists():
            raise AggregateError(f"{p}: path not found")
        if p.is_dir():
            found.extend(
                child
                for child in p.iterdir()
                if child.is_file() and child.suffix.lower() in (".xml", ".json")
            )
        else:
            found.append(p)
    return sorted(found, key=lambda x: x.name)


# ---------------------------------------------------------------------------
# Flaky detection
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class FlakyTest:
    """A test that both passed and failed/errored across the aggregated runs."""

    name: str
    passed: int          # number of runs in which it passed
    failed: int          # number of runs in which it failed or errored
    files: list[str]     # files (matrix legs) in which it appeared, sorted


def find_flaky_tests(runs: list[RunResult]) -> list[FlakyTest]:
    """Identify flaky tests across runs.

    A test is flaky when, grouped by its stable name, it has at least one
    PASSED execution and at least one FAILED *or* ERROR execution. An ERROR is
    treated as a failure for the purposes of flakiness; SKIPPED never counts as
    a pass or a fail.
    """
    passes: dict[str, int] = {}
    fails: dict[str, int] = {}
    files: dict[str, set[str]] = {}
    for run in runs:
        for case in run.cases:
            files.setdefault(case.name, set()).add(case.file)
            if case.status == PASSED:
                passes[case.name] = passes.get(case.name, 0) + 1
            elif case.status in (FAILED, ERROR):
                fails[case.name] = fails.get(case.name, 0) + 1

    flaky = [
        FlakyTest(
            name=name,
            passed=passes[name],
            failed=fails[name],
            files=sorted(files[name]),
        )
        for name in sorted(set(passes) & set(fails))
    ]
    return flaky


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------
@dataclass
class Aggregate:
    """Combined view over every run plus the detected flaky tests."""

    runs: list[RunResult]

    @property
    def flaky(self) -> list[FlakyTest]:
        return find_flaky_tests(self.runs)

    @property
    def passed(self) -> int:
        return sum(r.count(PASSED) for r in self.runs)

    @property
    def failed(self) -> int:
        return sum(r.count(FAILED) for r in self.runs)

    @property
    def errors(self) -> int:
        return sum(r.count(ERROR) for r in self.runs)

    @property
    def skipped(self) -> int:
        return sum(r.count(SKIPPED) for r in self.runs)

    @property
    def total(self) -> int:
        return sum(len(r.cases) for r in self.runs)

    @property
    def duration(self) -> float:
        return sum(r.duration for r in self.runs)

    @property
    def file_count(self) -> int:
        return len(self.runs)


def aggregate_results(paths: list[Path]) -> Aggregate:
    """Parse every result file under ``paths`` and combine them."""
    files = collect_result_files(paths)
    if not files:
        raise AggregateError(
            "no result files found (looked for .xml and .json files)"
        )
    runs = [parse_result_file(f) for f in files]
    return Aggregate(runs=runs)


# ---------------------------------------------------------------------------
# Markdown rendering (suitable for $GITHUB_STEP_SUMMARY)
# ---------------------------------------------------------------------------
def _fmt(seconds: float) -> str:
    """Format a duration in seconds with 2 decimals."""
    return f"{seconds:.2f}"


def render_markdown(agg: Aggregate) -> str:
    """Render the aggregate as a GitHub-flavoured Markdown job summary."""
    lines: list[str] = []
    lines.append("# Test Results Summary")
    lines.append("")
    lines.append(
        f"Aggregated **{agg.total}** test execution(s) across "
        f"**{agg.file_count}** result file(s)."
    )
    lines.append("")

    # Totals table.
    lines.append("| Status | Count |")
    lines.append("| --- | ---: |")
    lines.append(f"| Passed | {agg.passed} |")
    lines.append(f"| Failed | {agg.failed} |")
    lines.append(f"| Errors | {agg.errors} |")
    lines.append(f"| Skipped | {agg.skipped} |")
    lines.append(f"| **Total** | **{agg.total}** |")
    lines.append("")
    lines.append(f"**Total duration:** {_fmt(agg.duration)}s")
    lines.append("")

    # Flaky tests section.
    flaky = agg.flaky
    lines.append(f"## Flaky Tests ({len(flaky)})")
    lines.append("")
    if not flaky:
        lines.append("No flaky tests detected.")
    else:
        lines.append("These tests passed in some runs and failed in others.")
        lines.append("")
        lines.append("| Test | Passed | Failed | Files |")
        lines.append("| --- | ---: | ---: | --- |")
        for f in flaky:
            files = ", ".join(f.files)
            lines.append(f"| `{f.name}` | {f.passed} | {f.failed} | {files} |")
    lines.append("")

    # Per-file (per matrix leg) breakdown.
    lines.append("## Per-file Breakdown")
    lines.append("")
    lines.append("| File | Passed | Failed | Errors | Skipped | Duration |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    for run in agg.runs:
        lines.append(
            f"| `{run.file}` | {run.count(PASSED)} | {run.count(FAILED)} | "
            f"{run.count(ERROR)} | {run.count(SKIPPED)} | {_fmt(run.duration)}s |"
        )
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Machine-readable metrics (consumed by the CI pipeline / test harness)
# ---------------------------------------------------------------------------
def metrics_pairs(agg: Aggregate) -> list[tuple[str, str]]:
    """The aggregate as ordered ``(key, value)`` pairs of plain strings."""
    flaky_names = sorted(f.name for f in agg.flaky)
    return [
        ("passed", str(agg.passed)),
        ("failed", str(agg.failed)),
        ("errors", str(agg.errors)),
        ("skipped", str(agg.skipped)),
        ("total", str(agg.total)),
        ("duration", _fmt(agg.duration)),
        ("flaky_count", str(len(flaky_names))),
        ("flaky_tests", ",".join(flaky_names)),
    ]


# Markers delimit the metrics block in stdout so a CI step can grep it reliably.
METRICS_START = "=== AGGREGATE METRICS ==="
METRICS_END = "=== END METRICS ==="


def render_metrics_block(agg: Aggregate) -> str:
    body = "\n".join(f"{k}={v}" for k, v in metrics_pairs(agg))
    return f"{METRICS_START}\n{body}\n{METRICS_END}"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aggregate.py",
        description=(
            "Aggregate JUnit XML and JSON test result files into a Markdown "
            "summary, computing totals and flaky tests."
        ),
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="Result files (.xml/.json) or directories containing them.",
    )
    parser.add_argument(
        "--summary",
        metavar="FILE",
        help="Write the Markdown summary to FILE (e.g. $GITHUB_STEP_SUMMARY).",
    )
    parser.add_argument(
        "--github-output",
        metavar="FILE",
        help="Append key=value metrics to FILE (e.g. $GITHUB_OUTPUT) for job outputs.",
    )
    parser.add_argument(
        "--fail-on-failures",
        action="store_true",
        help="Exit non-zero if any test failed or errored (default: report only).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Entry point. Returns a process exit code."""
    args = _build_parser().parse_args(argv)

    # Aggregate, surfacing input problems as a clean error message + exit 2.
    try:
        agg = aggregate_results([Path(p) for p in args.paths])
    except AggregateError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    markdown = render_markdown(agg)

    # Always print the human summary plus a machine-readable metrics block to
    # stdout so the act-based harness can assert on exact values.
    print(markdown)
    print()
    print(render_metrics_block(agg))

    # Optionally mirror the Markdown into the GitHub Actions job summary.
    if args.summary:
        try:
            with open(args.summary, "a", encoding="utf-8") as fh:
                fh.write(markdown + "\n")
        except OSError as exc:
            print(f"error: could not write summary to {args.summary}: {exc}",
                  file=sys.stderr)
            return 2

    # Optionally expose metrics as GitHub Actions step outputs.
    if args.github_output:
        try:
            with open(args.github_output, "a", encoding="utf-8") as fh:
                for k, v in metrics_pairs(agg):
                    fh.write(f"{k}={v}\n")
        except OSError as exc:
            print(f"error: could not write outputs to {args.github_output}: {exc}",
                  file=sys.stderr)
            return 2

    if args.fail_on_failures and (agg.failed + agg.errors) > 0:
        return 1
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
