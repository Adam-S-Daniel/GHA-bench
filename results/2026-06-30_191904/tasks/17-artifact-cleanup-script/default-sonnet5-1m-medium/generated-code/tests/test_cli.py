"""
Red/Green TDD tests for the artifact-cleanup CLI entry point (cli.py).

The CLI loads artifact metadata from a JSON fixture file, applies a
retention policy built from CLI flags, and prints a deletion plan plus a
machine-parseable SUMMARY line (consumed by the GitHub Actions workflow).
"""
import json

import pytest

from cli import main


def _write_fixture(tmp_path, artifacts):
    fixture_path = tmp_path / "artifacts.json"
    fixture_path.write_text(json.dumps(artifacts))
    return str(fixture_path)


def test_cli_dry_run_reports_summary_without_deleting(tmp_path, capsys):
    # First failing test: dry-run mode prints a SUMMARY line and does not
    # claim any artifact was actually deleted.
    fixture = _write_fixture(
        tmp_path,
        [
            {
                "name": "old-build",
                "size_bytes": 500,
                "created_at": "2026-01-01T00:00:00+00:00",
                "workflow_run_id": "wf1",
            },
            {
                "name": "new-build",
                "size_bytes": 200,
                "created_at": "2026-01-30T00:00:00+00:00",
                "workflow_run_id": "wf1",
            },
        ],
    )

    exit_code = main(
        [
            "--fixture", fixture,
            "--now", "2026-01-31T00:00:00+00:00",
            "--max-age-days", "5",
            "--dry-run",
        ]
    )

    out = capsys.readouterr().out
    assert exit_code == 0
    assert "DRY RUN" in out
    assert "SUMMARY: artifacts_deleted=1 artifacts_retained=1 space_reclaimed_bytes=500" in out


def test_cli_live_run_reports_deletions_via_mock_deleter(tmp_path, capsys):
    # Second failing test: live run (no --dry-run) prints deletion actions
    # via the mock deleter and the same SUMMARY contract.
    fixture = _write_fixture(
        tmp_path,
        [
            {
                "name": "old-build",
                "size_bytes": 500,
                "created_at": "2026-01-01T00:00:00+00:00",
                "workflow_run_id": "wf1",
            },
        ],
    )

    exit_code = main(
        [
            "--fixture", fixture,
            "--now", "2026-01-31T00:00:00+00:00",
            "--max-age-days", "5",
        ]
    )

    out = capsys.readouterr().out
    assert exit_code == 0
    assert "LIVE RUN" in out
    assert "deleted: old-build" in out
    assert "SUMMARY: artifacts_deleted=1 artifacts_retained=0 space_reclaimed_bytes=500" in out


def test_cli_missing_fixture_file_exits_nonzero_with_message(capsys):
    # Third failing test: a missing fixture file is a graceful, meaningful
    # error, not an unhandled traceback.
    exit_code = main(["--fixture", "/no/such/file.json"])

    err = capsys.readouterr().err
    assert exit_code == 1
    assert "Fixture file not found" in err
