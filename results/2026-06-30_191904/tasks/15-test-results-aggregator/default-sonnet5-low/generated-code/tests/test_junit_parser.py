"""Tests for the JUnit XML parser. Written first (red) before any parser code exists."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from aggregator import parse_junit_xml, TestCaseResult

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "junit")


def test_parse_junit_returns_list_of_testcase_results():
    results = parse_junit_xml(os.path.join(FIXTURES, "run1.xml"))
    assert isinstance(results, list)
    assert len(results) == 4
    assert all(isinstance(r, TestCaseResult) for r in results)


def test_parse_junit_captures_pass_fail_skip_status():
    results = parse_junit_xml(os.path.join(FIXTURES, "run1.xml"))
    by_name = {r.name: r for r in results}
    assert by_name["test_add"].status == "passed"
    assert by_name["test_sub"].status == "failed"
    assert by_name["test_skip"].status == "skipped"
    assert by_name["test_flaky"].status == "passed"


def test_parse_junit_captures_classname_and_duration():
    results = parse_junit_xml(os.path.join(FIXTURES, "run1.xml"))
    test_add = next(r for r in results if r.name == "test_add")
    assert test_add.classname == "pkg.ModuleA"
    assert test_add.duration == 0.1


def test_parse_junit_missing_file_raises_clear_error():
    import pytest

    with pytest.raises(FileNotFoundError, match="not found"):
        parse_junit_xml("does/not/exist.xml")
