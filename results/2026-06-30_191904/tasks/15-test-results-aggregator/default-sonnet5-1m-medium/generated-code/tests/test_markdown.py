"""Tests for the Markdown summary renderer."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from aggregator import aggregate, render_markdown

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures")


def _matrix_paths():
    return [
        os.path.join(FIXTURES, "matrix_run_ubuntu.xml"),
        os.path.join(FIXTURES, "matrix_run_macos.json"),
    ]


def test_render_markdown_includes_totals_table():
    summary = aggregate(_matrix_paths())
    md = render_markdown(summary)

    assert "# Test Results Summary" in md
    assert "| Passed | Failed | Skipped | Total | Duration |" in md
    assert "| 4 " in md  # passed count appears in the totals row


def test_render_markdown_lists_flaky_tests():
    summary = aggregate(_matrix_paths())
    md = render_markdown(summary)

    assert "## Flaky Tests" in md
    assert "test_flaky_network_call" in md


def test_render_markdown_no_flaky_section_when_clean():
    summary = aggregate([os.path.join(FIXTURES, "junit_all_pass.xml")])
    md = render_markdown(summary)

    assert "No flaky tests detected" in md


def test_render_markdown_custom_title():
    summary = aggregate([os.path.join(FIXTURES, "junit_all_pass.xml")])
    md = render_markdown(summary, title="My Custom Title")

    assert "# My Custom Title" in md
