"""TDD cycle 5: the CLI — directory scanning, outputs, GITHUB_STEP_SUMMARY.

The CLI prints machine-readable TOTALS/FLAKY lines to stdout (asserted on by
the act harness), writes the markdown to --output, and appends the markdown
to $GITHUB_STEP_SUMMARY when that env var is set (as it is on GitHub Actions).
"""
from pathlib import Path

import pytest

from aggregator import main

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures"


def test_main_on_checked_in_fixtures(tmp_path, capsys, monkeypatch):
    """End-to-end over the repo fixtures: exact known-good numbers."""
    step_summary = tmp_path / "step_summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(step_summary))
    out_md = tmp_path / "summary.md"

    rc = main([str(FIXTURES), "--output", str(out_md)])
    assert rc == 0

    out = capsys.readouterr().out
    assert "TOTALS passed=7 failed=2 skipped=1 total=10 duration=7.00" in out
    assert "FLAKY shop.TestCore::test_flaky_network passes=2 failures=1" in out

    md = out_md.read_text()
    assert "| ✅ Passed | 7 |" in md
    assert "| `shop.TestCore::test_flaky_network` | 2 | 1 |" in md
    # Same markdown is appended to the GitHub Actions job summary file.
    assert step_summary.read_text() == md


def test_main_accepts_explicit_file_list(tmp_path, capsys, monkeypatch):
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)
    rc = main([str(FIXTURES / "matrix-linux.xml")])
    assert rc == 0
    out = capsys.readouterr().out
    assert "TOTALS passed=3 failed=0 skipped=1 total=4 duration=2.00" in out
    assert "FLAKY none" in out


def test_main_errors_cleanly_on_empty_directory(tmp_path, capsys):
    rc = main([str(tmp_path)])
    assert rc == 2
    assert "no result files (*.xml, *.json) found" in capsys.readouterr().err


def test_main_errors_cleanly_on_bad_input(tmp_path, capsys):
    bad = tmp_path / "bad.xml"
    bad.write_text("<oops")
    rc = main([str(bad)])
    assert rc == 2
    assert "not valid XML" in capsys.readouterr().err
