"""Tests for the aggregator.py CLI entry point (main())."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import aggregator

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


def test_main_returns_zero_when_no_failures(capsys):
    path = os.path.join(FIXTURES, "junit_all_pass.xml")
    rc = aggregator.main([path])

    assert rc == 0
    captured = capsys.readouterr()
    assert "Test Results Summary" in captured.out


def test_main_returns_nonzero_when_failures_present(capsys):
    path = os.path.join(FIXTURES, "junit_with_failure.xml")
    rc = aggregator.main([path])

    assert rc == 1


def test_main_returns_two_when_no_args(capsys):
    rc = aggregator.main([])
    assert rc == 2


def test_main_writes_to_github_step_summary_when_set(tmp_path, monkeypatch):
    summary_file = tmp_path / "step_summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

    path = os.path.join(FIXTURES, "junit_all_pass.xml")
    aggregator.main([path])

    content = summary_file.read_text()
    assert "Test Results Summary" in content


def test_main_reports_error_for_missing_file(capsys):
    rc = aggregator.main([os.path.join(FIXTURES, "nope.xml")])
    assert rc == 1
    captured = capsys.readouterr()
    assert "Error:" in captured.err
