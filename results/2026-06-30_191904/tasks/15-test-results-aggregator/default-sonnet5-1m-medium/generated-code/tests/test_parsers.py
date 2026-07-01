"""
Tests for the format parsers (JUnit XML and JSON) in aggregator.py.

TDD note: this file is written BEFORE aggregator.py exists, so the first
run of `pytest tests/` is expected to fail with an ImportError / collection
error. That is the "red" step.
"""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from aggregator import parse_junit_xml, CaseResult


FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


def test_parse_junit_xml_returns_test_cases():
    path = os.path.join(FIXTURES, "junit_all_pass.xml")
    cases = parse_junit_xml(path)

    assert len(cases) == 2
    assert all(isinstance(c, CaseResult) for c in cases)
    names = {c.name for c in cases}
    assert names == {"test_addition", "test_subtraction"}


def test_parse_junit_xml_marks_status_correctly():
    path = os.path.join(FIXTURES, "junit_with_failure.xml")
    cases = parse_junit_xml(path)

    by_name = {c.name: c for c in cases}
    assert by_name["test_addition"].status == "passed"
    assert by_name["test_division"].status == "failed"
    assert by_name["test_skipped_feature"].status == "skipped"
