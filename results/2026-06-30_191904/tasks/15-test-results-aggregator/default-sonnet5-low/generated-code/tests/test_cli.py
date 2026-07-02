"""Tests for the CLI entry point (main()) used by the GitHub Actions workflow."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from aggregator import main

JUNIT_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "junit")
JSON_FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "json")


def test_main_writes_markdown_to_output_path(tmp_path):
    out = tmp_path / "summary.md"
    exit_code = main(
        [
            os.path.join(JUNIT_FIXTURES, "run1.xml"),
            os.path.join(JUNIT_FIXTURES, "run2.xml"),
            os.path.join(JSON_FIXTURES, "run3.json"),
            "--output",
            str(out),
        ]
    )
    assert exit_code == 1  # non-zero because there are failed tests
    content = out.read_text()
    assert "# Test Results Summary" in content
    assert "| Failed | 3 |" in content


def test_main_returns_zero_when_no_failures(tmp_path):
    out = tmp_path / "summary.md"
    exit_code = main(
        [
            os.path.join(JSON_FIXTURES, "run_all_pass.json"),
            "--output",
            str(out),
        ]
    )
    assert exit_code == 0
    assert "| Failed | 0 |" in out.read_text()


def test_main_returns_nonzero_and_error_message_for_missing_file(tmp_path, capsys):
    out = tmp_path / "summary.md"
    exit_code = main(["does/not/exist.xml", "--output", str(out)])
    assert exit_code == 2
    captured = capsys.readouterr()
    assert "not found" in captured.err
