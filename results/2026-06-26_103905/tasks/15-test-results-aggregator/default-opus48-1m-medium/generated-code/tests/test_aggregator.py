# TDD test suite for the test-results aggregator.
#
# Approach: each piece of functionality (JUnit parsing, JSON parsing, format
# dispatch, aggregation, flaky detection, markdown generation, CLI) gets its own
# test written *before* the implementation. We exercise the public API exposed by
# aggregator.py. Fixtures on disk live under fixtures/; tests that need bespoke
# inputs build them in a tmp_path so the assertions stay self-contained.

import json
import subprocess
import sys
from pathlib import Path

import pytest

# Make the project root importable regardless of where pytest is invoked from.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import aggregator  # noqa: E402
from aggregator import (  # noqa: E402
    TestCase,
    aggregate,
    find_flaky,
    generate_markdown,
    parse_file,
    parse_json,
    parse_junit_xml,
)


# --------------------------------------------------------------------------- #
# JUnit XML parsing
# --------------------------------------------------------------------------- #

JUNIT_SAMPLE = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="suite.A" tests="4" failures="1" skipped="1" time="3.5">
    <testcase classname="suite.A" name="test_pass" time="1.0"/>
    <testcase classname="suite.A" name="test_fail" time="0.5">
      <failure message="boom">AssertionError</failure>
    </testcase>
    <testcase classname="suite.A" name="test_error" time="0.5">
      <error message="kaboom">RuntimeError</error>
    </testcase>
    <testcase classname="suite.A" name="test_skip" time="0.0">
      <skipped message="nope"/>
    </testcase>
  </testsuite>
</testsuites>
"""


def test_parse_junit_xml_counts_and_statuses(tmp_path):
    p = tmp_path / "r.xml"
    p.write_text(JUNIT_SAMPLE)
    cases = parse_junit_xml(p)
    assert len(cases) == 4
    by_name = {c.name: c for c in cases}
    assert by_name["test_pass"].status == "passed"
    assert by_name["test_fail"].status == "failed"
    # <error> is treated as a failure for aggregation purposes.
    assert by_name["test_error"].status == "failed"
    assert by_name["test_skip"].status == "skipped"
    assert by_name["test_pass"].duration == pytest.approx(1.0)
    assert by_name["test_pass"].classname == "suite.A"


def test_parse_junit_xml_missing_file_raises():
    with pytest.raises(FileNotFoundError):
        parse_junit_xml(Path("does-not-exist.xml"))


def test_parse_junit_xml_malformed_raises(tmp_path):
    p = tmp_path / "bad.xml"
    p.write_text("<testsuite><testcase></broken>")
    with pytest.raises(ValueError) as exc:
        parse_junit_xml(p)
    assert "bad.xml" in str(exc.value)


# --------------------------------------------------------------------------- #
# JSON parsing
# --------------------------------------------------------------------------- #

JSON_SAMPLE = {
    "tests": [
        {"name": "test_pass", "classname": "suite.B", "status": "passed", "duration": 2.0},
        {"name": "test_fail", "classname": "suite.B", "status": "failed", "duration": 1.0},
        {"name": "test_skip", "classname": "suite.B", "status": "skipped", "duration": 0.0},
    ]
}


def test_parse_json_counts_and_statuses(tmp_path):
    p = tmp_path / "r.json"
    p.write_text(json.dumps(JSON_SAMPLE))
    cases = parse_json(p)
    assert len(cases) == 3
    by_name = {c.name: c for c in cases}
    assert by_name["test_pass"].status == "passed"
    assert by_name["test_fail"].status == "failed"
    assert by_name["test_skip"].status == "skipped"
    assert by_name["test_pass"].duration == pytest.approx(2.0)


def test_parse_json_normalizes_status_aliases(tmp_path):
    p = tmp_path / "alias.json"
    p.write_text(json.dumps({"tests": [
        {"name": "a", "status": "pass", "duration": 0},
        {"name": "b", "status": "FAIL", "duration": 0},
        {"name": "c", "status": "error", "duration": 0},
        {"name": "d", "status": "skip", "duration": 0},
    ]}))
    statuses = {c.name: c.status for c in parse_json(p)}
    assert statuses == {"a": "passed", "b": "failed", "c": "failed", "d": "skipped"}


def test_parse_json_invalid_raises(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not json")
    with pytest.raises(ValueError) as exc:
        parse_json(p)
    assert "bad.json" in str(exc.value)


def test_parse_json_unknown_status_raises(tmp_path):
    p = tmp_path / "weird.json"
    p.write_text(json.dumps({"tests": [{"name": "a", "status": "wat"}]}))
    with pytest.raises(ValueError) as exc:
        parse_json(p)
    assert "wat" in str(exc.value)


# --------------------------------------------------------------------------- #
# Format dispatch
# --------------------------------------------------------------------------- #

def test_parse_file_dispatches_by_extension(tmp_path):
    xml = tmp_path / "a.xml"
    xml.write_text(JUNIT_SAMPLE)
    js = tmp_path / "b.json"
    js.write_text(json.dumps(JSON_SAMPLE))
    assert len(parse_file(xml)) == 4
    assert len(parse_file(js)) == 3


def test_parse_file_unknown_extension_raises(tmp_path):
    p = tmp_path / "a.txt"
    p.write_text("hi")
    with pytest.raises(ValueError):
        parse_file(p)


# --------------------------------------------------------------------------- #
# Aggregation + flaky detection
# --------------------------------------------------------------------------- #

def test_aggregate_totals():
    cases = [
        TestCase("suite", "a", "passed", 1.0, "run1"),
        TestCase("suite", "b", "failed", 2.0, "run1"),
        TestCase("suite", "c", "skipped", 0.0, "run1"),
        TestCase("suite", "a", "passed", 1.5, "run2"),
    ]
    agg = aggregate(cases)
    assert agg["total"] == 4
    assert agg["passed"] == 2
    assert agg["failed"] == 1
    assert agg["skipped"] == 1
    assert agg["duration"] == pytest.approx(4.5)


def test_find_flaky_identifies_mixed_results():
    # "a" passes in run1 and fails in run2 -> flaky.
    # "b" fails twice -> consistently failing, not flaky.
    cases = [
        TestCase("suite", "a", "passed", 1.0, "run1"),
        TestCase("suite", "a", "failed", 1.0, "run2"),
        TestCase("suite", "b", "failed", 1.0, "run1"),
        TestCase("suite", "b", "failed", 1.0, "run2"),
    ]
    flaky = find_flaky(cases)
    names = {f["id"] for f in flaky}
    assert "suite.a" in names
    assert "suite.b" not in names


def test_find_flaky_skipped_does_not_count_as_failure():
    cases = [
        TestCase("suite", "a", "passed", 1.0, "run1"),
        TestCase("suite", "a", "skipped", 0.0, "run2"),
    ]
    assert find_flaky(cases) == []


# --------------------------------------------------------------------------- #
# Markdown generation
# --------------------------------------------------------------------------- #

def test_generate_markdown_contains_totals_and_flaky():
    cases = [
        TestCase("suite", "a", "passed", 1.0, "run1"),
        TestCase("suite", "a", "failed", 1.0, "run2"),
        TestCase("suite", "b", "passed", 2.0, "run1"),
    ]
    md = generate_markdown(cases)
    assert "# Test Results Summary" in md
    assert "| 3 |" in md  # total cell
    assert "Flaky Tests" in md
    assert "suite.a" in md
    # A clean test should not be listed as flaky.
    flaky_section = md.split("Flaky Tests", 1)[1]
    assert "suite.b" not in flaky_section


def test_generate_markdown_no_flaky_states_none():
    cases = [TestCase("suite", "a", "passed", 1.0, "run1")]
    md = generate_markdown(cases)
    assert "No flaky tests detected" in md


# --------------------------------------------------------------------------- #
# Fixtures on disk exist and are parseable
# --------------------------------------------------------------------------- #

def test_repo_fixtures_are_parseable():
    fixtures = ROOT / "fixtures"
    files = list(fixtures.glob("*.xml")) + list(fixtures.glob("*.json"))
    assert files, "expected sample fixtures to exist"
    for f in files:
        cases = parse_file(f)
        assert isinstance(cases, list)


# --------------------------------------------------------------------------- #
# CLI end-to-end
# --------------------------------------------------------------------------- #

def test_cli_writes_summary(tmp_path):
    xml = tmp_path / "run1.xml"
    xml.write_text(JUNIT_SAMPLE)
    js = tmp_path / "run2.json"
    js.write_text(json.dumps({"tests": [
        {"name": "test_pass", "classname": "suite.A", "status": "failed", "duration": 1.0},
    ]}))
    out = tmp_path / "summary.md"
    result = subprocess.run(
        [sys.executable, str(ROOT / "aggregator.py"),
         "--output", str(out), str(xml), str(js)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    md = out.read_text()
    assert "# Test Results Summary" in md
    # test_pass passed in run1, failed in run2 -> flaky.
    assert "test_pass" in md.split("Flaky Tests", 1)[1]


def test_cli_errors_on_missing_file(tmp_path):
    result = subprocess.run(
        [sys.executable, str(ROOT / "aggregator.py"), str(tmp_path / "nope.xml")],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "nope.xml" in result.stderr
