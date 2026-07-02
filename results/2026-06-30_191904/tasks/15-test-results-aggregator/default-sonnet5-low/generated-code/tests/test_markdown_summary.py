"""Tests for the Markdown job-summary generator."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from aggregator import (
    load_all_results,
    aggregate_results,
    detect_flaky_tests,
    render_markdown_summary,
)

JUNIT_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "junit")
JSON_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "json")


def _build():
    files = [
        os.path.join(JUNIT_FIXTURES, "run1.xml"),
        os.path.join(JUNIT_FIXTURES, "run2.xml"),
        os.path.join(JSON_FIXTURES, "run3.json"),
    ]
    results = load_all_results(files)
    totals = aggregate_results(results)
    flaky = detect_flaky_tests(results)
    return totals, flaky


def test_render_markdown_includes_heading():
    totals, flaky = _build()
    md = render_markdown_summary(totals, flaky, num_files=3)
    assert md.startswith("# Test Results Summary")


def test_render_markdown_includes_totals_table():
    totals, flaky = _build()
    md = render_markdown_summary(totals, flaky, num_files=3)
    assert "| Total | 12 |" in md
    assert "| Passed | 6 |" in md
    assert "| Failed | 3 |" in md
    assert "| Skipped | 3 |" in md
    assert "3 files" in md


def test_render_markdown_includes_flaky_section_when_flaky_tests_exist():
    totals, flaky = _build()
    md = render_markdown_summary(totals, flaky, num_files=3)
    assert "## Flaky Tests" in md
    assert "pkg.ModuleA::test_sub" in md
    assert "pkg.ModuleB::test_flaky" in md


def test_render_markdown_omits_flaky_section_when_no_flaky_tests():
    totals, _ = _build()
    md = render_markdown_summary(totals, [], num_files=3)
    assert "## Flaky Tests" not in md
    assert "No flaky tests detected" in md


def test_render_markdown_shows_failure_status_emoji_when_failures_present():
    totals, flaky = _build()
    md = render_markdown_summary(totals, flaky, num_files=3)
    assert "❌" in md  # cross mark, since totals.failed > 0
