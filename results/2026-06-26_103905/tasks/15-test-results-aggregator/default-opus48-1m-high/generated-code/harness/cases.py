"""Test-case definitions shared by the act harness.

Each case is a self-contained matrix-build scenario: a set of fixture files
(written into ``test-results/``) plus the EXACT report lines the aggregator
must emit for that input. Keeping fixtures and expectations together makes the
assertions in the harness known-good rather than "some output appeared".
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Case:
    name: str
    files: dict[str, str]  # filename in test-results/ -> file content
    expected_lines: list[str]  # exact substrings that must appear in act output


# --- Case A: a classic flaky matrix (the committed default test-results/) -----
# ubuntu leg passes `flaky`, macos leg fails it -> one flaky test, verdict FAIL.
CASE_FLAKY_MATRIX = Case(
    name="flaky-matrix",
    files={
        "ubuntu.xml": (
            '<testsuites>\n'
            '  <testsuite name="m" tests="3" failures="0" skipped="1" time="0.30">\n'
            '    <testcase classname="c" name="a" time="0.10"/>\n'
            '    <testcase classname="c" name="flaky" time="0.20"/>\n'
            '    <testcase classname="c" name="net" time="0.00"><skipped/></testcase>\n'
            '  </testsuite>\n'
            '</testsuites>\n'
        ),
        "macos.json": (
            '{"tests": [\n'
            '  {"classname": "c", "name": "a", "status": "passed", "duration": 0.15},\n'
            '  {"classname": "c", "name": "flaky", "status": "failed", "duration": 0.25},\n'
            '  {"classname": "c", "name": "net", "status": "skipped", "duration": 0.0}\n'
            ']}\n'
        ),
    },
    expected_lines=[
        "- **Total tests:** 6",
        "- **Passed:** 3",
        "- **Failed:** 1",
        "- **Skipped:** 2",
        "- **Total duration:** 0.70s",
        "- **Files aggregated:** 2",
        "| macos.json | 1 | 1 | 1 | 0.40s |",
        "| ubuntu.xml | 2 | 0 | 1 | 0.30s |",
        "- `c::flaky`",
        "**Overall result:** FAILED",
    ],
)

# --- Case B: everything green, single file, no flaky tests --------------------
CASE_ALL_GREEN = Case(
    name="all-green",
    files={
        "results.xml": (
            '<testsuite name="s" tests="2" failures="0" skipped="0" time="3.0">\n'
            '  <testcase classname="c" name="x" time="1.00"/>\n'
            '  <testcase classname="c" name="y" time="2.00"/>\n'
            '</testsuite>\n'
        ),
    },
    expected_lines=[
        "- **Total tests:** 2",
        "- **Passed:** 2",
        "- **Failed:** 0",
        "- **Skipped:** 0",
        "- **Total duration:** 3.00s",
        "- **Files aggregated:** 1",
        "| results.xml | 2 | 0 | 0 | 3.00s |",
        "No flaky tests detected.",
        "**Overall result:** PASSED",
    ],
)

# --- Case C: three files, flaky test (`t::b`) spread across mixed formats ------
CASE_THREE_FILES = Case(
    name="three-files",
    files={
        "r1.xml": (
            '<testsuite name="s"><testcase classname="t" name="a" time="0.50"/>'
            '<testcase classname="t" name="b" time="0.50"/></testsuite>\n'
        ),
        "r2.json": (
            '{"tests": [\n'
            '  {"classname": "t", "name": "a", "status": "passed", "duration": 0.5},\n'
            '  {"classname": "t", "name": "b", "status": "failed", "duration": 0.5}\n'
            ']}\n'
        ),
        "r3.xml": (
            '<testsuite name="s"><testcase classname="t" name="a" time="0.50"/>'
            '<testcase classname="t" name="b" time="0.50"/></testsuite>\n'
        ),
    },
    expected_lines=[
        "- **Total tests:** 6",
        "- **Passed:** 5",
        "- **Failed:** 1",
        "- **Skipped:** 0",
        "- **Total duration:** 3.00s",
        "- **Files aggregated:** 3",
        "| r1.xml | 2 | 0 | 0 | 1.00s |",
        "| r2.json | 1 | 1 | 0 | 1.00s |",
        "| r3.xml | 2 | 0 | 0 | 1.00s |",
        "- `t::b`",
        "**Overall result:** FAILED",
    ],
)


ALL_CASES = [CASE_FLAKY_MATRIX, CASE_ALL_GREEN, CASE_THREE_FILES]
