"""Tests for the JSON test-result parser."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from aggregator import parse_json_results, AggregatorError

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


def test_parse_json_results_returns_test_cases():
    path = os.path.join(FIXTURES, "results_all_pass.json")
    cases = parse_json_results(path)

    assert len(cases) == 2
    statuses = {c.status for c in cases}
    assert statuses == {"passed"}


def test_parse_json_results_marks_status_correctly():
    path = os.path.join(FIXTURES, "results_with_failure.json")
    cases = parse_json_results(path)

    by_name = {c.name: c for c in cases}
    assert by_name["test_login"].status == "passed"
    assert by_name["test_logout"].status == "failed"
    assert by_name["test_password_reset"].status == "skipped"


def test_parse_json_results_missing_file_raises():
    try:
        parse_json_results(os.path.join(FIXTURES, "does_not_exist.json"))
        assert False, "expected AggregatorError"
    except AggregatorError as exc:
        assert "not found" in str(exc)


def test_parse_json_results_malformed_raises_meaningful_error():
    path = os.path.join(FIXTURES, "results_malformed.json")
    try:
        parse_json_results(path)
        assert False, "expected AggregatorError"
    except AggregatorError as exc:
        assert "Failed to parse" in str(exc)
