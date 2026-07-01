"""Tests for the JSON test-result parser."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest

from aggregator import parse_json_results

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "json")


def test_parse_json_returns_list_of_testcase_results():
    results = parse_json_results(os.path.join(FIXTURES, "run3.json"))
    assert len(results) == 4


def test_parse_json_captures_status_and_message():
    results = parse_json_results(os.path.join(FIXTURES, "run3.json"))
    by_name = {r.name: r for r in results}
    assert by_name["test_multiply"].status == "passed"
    assert by_name["test_divide"].status == "failed"
    assert by_name["test_divide"].message == "ZeroDivisionError"
    assert by_name["test_skip"].status == "skipped"


def test_parse_json_missing_file_raises_clear_error():
    with pytest.raises(FileNotFoundError, match="not found"):
        parse_json_results("does/not/exist.json")


def test_parse_json_malformed_raises_value_error(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{not valid json")
    with pytest.raises(ValueError, match="Invalid JSON"):
        parse_json_results(str(bad))
