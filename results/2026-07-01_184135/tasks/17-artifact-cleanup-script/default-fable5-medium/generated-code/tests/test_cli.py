"""CLI-level tests: dry-run vs execute, summary output, error handling.

The CLI is exercised in-process via run_cli(argv) -> exit code, with
output captured through capsys. Fixture data lives in tmp JSON files.
"""

import json

import pytest

from artifact_cleanup import run_cli


SAMPLE = [
    # run 100: three artifacts, one of which is over 30 days old
    {"name": "logs-old", "size_bytes": 500, "created_at": "2026-05-01T00:00:00Z", "workflow_run_id": 100},
    {"name": "logs-mid", "size_bytes": 300, "created_at": "2026-06-28T00:00:00Z", "workflow_run_id": 100},
    {"name": "logs-new", "size_bytes": 200, "created_at": "2026-06-30T00:00:00Z", "workflow_run_id": 100},
    # run 200: a single fresh artifact
    {"name": "dist", "size_bytes": 1000, "created_at": "2026-06-29T00:00:00Z", "workflow_run_id": 200},
]


@pytest.fixture
def sample_file(tmp_path):
    path = tmp_path / "artifacts.json"
    path.write_text(json.dumps(SAMPLE))
    return str(path)


def run(args):
    return run_cli(args)


class TestDryRun:
    def test_dry_run_reports_plan_without_deleting(self, sample_file, capsys):
        # max-age 30 kills logs-old; keep-latest-2 kills nothing else
        # (logs-old is already gone, leaving 2 in run 100).
        code = run(
            [
                "--input", sample_file,
                "--max-age-days", "30",
                "--keep-latest", "2",
                "--now", "2026-07-01T00:00:00Z",
                "--dry-run",
            ]
        )
        out = capsys.readouterr().out
        assert code == 0
        assert "DRY_RUN=true" in out
        assert "DELETED_COUNT=1" in out
        assert "RETAINED_COUNT=3" in out
        assert "SPACE_RECLAIMED_BYTES=500" in out
        assert "RETAINED_BYTES=1500" in out
        assert "DELETE logs-old (500 bytes) - exceeds max age of 30 days" in out
        # dry-run must not claim to have deleted anything
        assert "Deleted artifact" not in out

    def test_execute_mode_performs_mock_deletions(self, sample_file, capsys):
        code = run(
            [
                "--input", sample_file,
                "--max-total-size", "1200",
                "--now", "2026-07-01T00:00:00Z",
            ]
        )
        out = capsys.readouterr().out
        assert code == 0
        assert "DRY_RUN=false" in out
        # budget 1200: evict oldest first -> logs-old (500), then logs-mid (300)
        # leaves 1200 <= 1200.
        assert "DELETED_COUNT=2" in out
        assert "RETAINED_COUNT=2" in out
        assert "SPACE_RECLAIMED_BYTES=800" in out
        assert "Deleted artifact 'logs-old'" in out
        assert "Deleted artifact 'logs-mid'" in out


class TestCliErrors:
    def test_missing_input_file(self, capsys):
        code = run(["--input", "/nonexistent/artifacts.json"])
        err = capsys.readouterr().err
        assert code == 2
        assert "cannot read input file" in err

    def test_invalid_json(self, tmp_path, capsys):
        bad = tmp_path / "bad.json"
        bad.write_text("{not json")
        code = run(["--input", str(bad)])
        err = capsys.readouterr().err
        assert code == 2
        assert "not valid JSON" in err

    def test_invalid_record_surfaces_cleanup_error(self, tmp_path, capsys):
        bad = tmp_path / "bad.json"
        bad.write_text(json.dumps([{"name": "x"}]))
        code = run(["--input", str(bad)])
        err = capsys.readouterr().err
        assert code == 2
        assert "missing required field" in err

    def test_invalid_now_value(self, sample_file, capsys):
        code = run(["--input", sample_file, "--now", "not-a-date"])
        err = capsys.readouterr().err
        assert code == 2
        assert "invalid --now" in err
