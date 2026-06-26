"""Red/green TDD for log parsing, changelog rendering and file updates."""
import json

from bump_version import (
    parse_commit_log,
    generate_changelog,
    update_version_file,
)


def test_parse_commit_log_splits_on_records(tmp_path):
    # Commits are separated by a NUL byte so multi-line bodies stay intact
    # (this is what `git log -z --format=%B` produces).
    log = tmp_path / "commits.log"
    log.write_text("feat: a\x00fix: b\x00chore: c")
    assert parse_commit_log(str(log)) == ["feat: a", "fix: b", "chore: c"]


def test_parse_commit_log_ignores_blank_records(tmp_path):
    log = tmp_path / "commits.log"
    log.write_text("feat: a\x00\x00\x00")
    assert parse_commit_log(str(log)) == ["feat: a"]


def test_generate_changelog_groups_by_type():
    commits = [
        "feat: add login",
        "fix: handle null",
        "feat(api)!: drop v1",
        "chore: noise",  # filtered out of the changelog
    ]
    entry = generate_changelog("2.0.0", commits, date="2026-06-26")
    assert "## 2.0.0 - 2026-06-26" in entry
    assert "### Breaking Changes" in entry
    assert "- drop v1" in entry
    assert "### Features" in entry
    assert "- add login" in entry
    assert "### Fixes" in entry
    assert "- handle null" in entry
    # Non-conventional noise must not leak in.
    assert "noise" not in entry


def test_update_version_file_plain(tmp_path):
    vfile = tmp_path / "VERSION"
    vfile.write_text("1.0.0\n")
    update_version_file(str(vfile), "1.1.0")
    assert vfile.read_text().strip() == "1.1.0"


def test_update_version_file_package_json_preserves_other_keys(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(json.dumps({"name": "demo", "version": "1.0.0"}))
    update_version_file(str(pkg), "1.1.0")
    data = json.loads(pkg.read_text())
    assert data["version"] == "1.1.0"
    assert data["name"] == "demo"
