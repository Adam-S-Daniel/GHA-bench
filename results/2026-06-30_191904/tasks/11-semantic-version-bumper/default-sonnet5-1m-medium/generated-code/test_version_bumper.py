"""
Red/green TDD test suite for version_bumper.py.

Each test below was written BEFORE its corresponding implementation existed
(or before the implementation handled that case), then the minimum code was
added to version_bumper.py to make it pass. Run with:  python3 -m pytest -v
"""
import json
import os
import subprocess
import sys
import tempfile

import pytest

import version_bumper as vb


# ---------------------------------------------------------------------------
# 1. parse_version
# ---------------------------------------------------------------------------

def test_parse_version_returns_major_minor_patch_tuple():
    assert vb.parse_version("1.2.3") == (1, 2, 3)


def test_parse_version_rejects_malformed_string():
    with pytest.raises(vb.VersionBumperError) as exc:
        vb.parse_version("not-a-version")
    assert "not-a-version" in str(exc.value)


# ---------------------------------------------------------------------------
# 2. classify_commit / determine_bump
# ---------------------------------------------------------------------------

def test_classify_commit_detects_fix_as_patch():
    assert vb.classify_commit("fix: correct off-by-one error") == "patch"


def test_classify_commit_detects_feat_as_minor():
    assert vb.classify_commit("feat: add dark mode toggle") == "minor"


def test_classify_commit_detects_breaking_bang_as_major():
    assert vb.classify_commit("feat!: drop support for Node 12") == "major"


def test_classify_commit_detects_breaking_change_footer_as_major():
    msg = "refactor: rework auth\n\nBREAKING CHANGE: tokens are now opaque"
    assert vb.classify_commit(msg) == "major"


def test_classify_commit_returns_none_for_chore():
    assert vb.classify_commit("chore: update dependencies") is None


def test_determine_bump_picks_highest_severity_across_commits():
    commits = ["chore: cleanup", "fix: patch bug", "feat: new widget"]
    assert vb.determine_bump(commits) == "minor"


def test_determine_bump_prefers_major_over_others():
    commits = ["fix: patch bug", "feat!: breaking api change"]
    assert vb.determine_bump(commits) == "major"


def test_determine_bump_returns_none_when_nothing_bumpable():
    commits = ["chore: cleanup", "docs: typo fix in readme"]
    assert vb.determine_bump(commits) is None


def test_determine_bump_raises_on_empty_commit_list():
    with pytest.raises(vb.VersionBumperError):
        vb.determine_bump([])


# ---------------------------------------------------------------------------
# 3. bump_version
# ---------------------------------------------------------------------------

def test_bump_version_patch():
    assert vb.bump_version((1, 2, 3), "patch") == "1.2.4"


def test_bump_version_minor_resets_patch():
    assert vb.bump_version((1, 2, 3), "minor") == "1.3.0"


def test_bump_version_major_resets_minor_and_patch():
    assert vb.bump_version((1, 2, 3), "major") == "2.0.0"


def test_bump_version_rejects_unknown_bump_type():
    with pytest.raises(vb.VersionBumperError):
        vb.bump_version((1, 2, 3), "supermajor")


# ---------------------------------------------------------------------------
# 4. reading version files (plain VERSION file and package.json)
# ---------------------------------------------------------------------------

def test_read_version_file_plain_text(tmp_path):
    f = tmp_path / "VERSION"
    f.write_text("1.2.3\n")
    assert vb.read_version_file(str(f)) == "1.2.3"


def test_read_version_file_package_json(tmp_path):
    f = tmp_path / "package.json"
    f.write_text(json.dumps({"name": "demo", "version": "1.2.3"}))
    assert vb.read_version_file(str(f)) == "1.2.3"


def test_read_version_file_missing_raises(tmp_path):
    with pytest.raises(vb.VersionBumperError):
        vb.read_version_file(str(tmp_path / "does-not-exist.json"))


def test_read_version_file_package_json_without_version_key_raises(tmp_path):
    f = tmp_path / "package.json"
    f.write_text(json.dumps({"name": "demo"}))
    with pytest.raises(vb.VersionBumperError):
        vb.read_version_file(str(f))


# ---------------------------------------------------------------------------
# 5. writing version files
# ---------------------------------------------------------------------------

def test_write_version_file_plain_text(tmp_path):
    f = tmp_path / "VERSION"
    f.write_text("1.2.3\n")
    vb.write_version_file(str(f), "1.3.0")
    assert f.read_text().strip() == "1.3.0"


def test_write_version_file_package_json_preserves_other_keys(tmp_path):
    f = tmp_path / "package.json"
    f.write_text(json.dumps({"name": "demo", "version": "1.2.3"}, indent=2))
    vb.write_version_file(str(f), "1.3.0")
    data = json.loads(f.read_text())
    assert data["version"] == "1.3.0"
    assert data["name"] == "demo"


# ---------------------------------------------------------------------------
# 6. changelog generation
# ---------------------------------------------------------------------------

def test_generate_changelog_entry_groups_commits_by_type():
    commits = ["feat: add widget", "fix: crash on startup", "chore: bump ci"]
    entry = vb.generate_changelog_entry("1.3.0", "2026-07-01", commits)
    assert "## 1.3.0 - 2026-07-01" in entry
    assert "### Features" in entry
    assert "- add widget" in entry
    assert "### Bug Fixes" in entry
    assert "- crash on startup" in entry
    # non-bumpable commit types are omitted from the changelog body
    assert "bump ci" not in entry


def test_prepend_changelog_creates_file_if_missing(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    entry = "## 1.0.0 - 2026-07-01\n\n- first release\n"
    vb.prepend_changelog(str(changelog), entry)
    assert changelog.read_text().startswith("## 1.0.0 - 2026-07-01")


def test_prepend_changelog_puts_new_entry_above_old_ones(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text("## 0.9.0 - 2026-06-01\n\n- old stuff\n")
    vb.prepend_changelog(str(changelog), "## 1.0.0 - 2026-07-01\n\n- new stuff\n")
    text = changelog.read_text()
    assert text.index("1.0.0") < text.index("0.9.0")


# ---------------------------------------------------------------------------
# 7. reading a mock commit log fixture (list of commit subjects, one per line)
# ---------------------------------------------------------------------------

def test_read_commits_file_splits_on_blank_line_separated_records(tmp_path):
    f = tmp_path / "commits.txt"
    f.write_text("feat: add widget\n---\nfix: crash on startup\n---\nchore: bump ci\n")
    commits = vb.read_commits_file(str(f))
    assert commits == [
        "feat: add widget",
        "fix: crash on startup",
        "chore: bump ci",
    ]


def test_read_commits_file_preserves_multiline_breaking_change_footer(tmp_path):
    f = tmp_path / "commits.txt"
    f.write_text("refactor: rework auth\n\nBREAKING CHANGE: tokens are now opaque\n")
    commits = vb.read_commits_file(str(f))
    assert commits == ["refactor: rework auth\n\nBREAKING CHANGE: tokens are now opaque"]


# ---------------------------------------------------------------------------
# 8. end-to-end CLI test using the fixture files committed to fixtures/
# ---------------------------------------------------------------------------

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


def _run_cli(tmp_path, version_fixture, commits_fixture):
    version_file = tmp_path / "VERSION"
    commits_file = tmp_path / "commits.txt"
    changelog_file = tmp_path / "CHANGELOG.md"
    version_file.write_text(open(os.path.join(FIXTURES_DIR, version_fixture)).read())
    commits_file.write_text(open(os.path.join(FIXTURES_DIR, commits_fixture)).read())
    result = subprocess.run(
        [
            sys.executable,
            os.path.join(os.path.dirname(__file__), "version_bumper.py"),
            "--version-file", str(version_file),
            "--commits-file", str(commits_file),
            "--changelog-file", str(changelog_file),
            "--date", "2026-07-01",
        ],
        capture_output=True,
        text=True,
    )
    return result, version_file, changelog_file


def test_cli_bumps_patch_version_from_fix_commits(tmp_path):
    result, version_file, changelog_file = _run_cli(
        tmp_path, "version_1.0.0.txt", "commits_fix.txt"
    )
    assert result.returncode == 0, result.stderr
    assert "1.0.1" in result.stdout
    assert version_file.read_text().strip() == "1.0.1"
    assert "## 1.0.1" in changelog_file.read_text()


def test_cli_bumps_minor_version_from_feat_commits(tmp_path):
    result, version_file, changelog_file = _run_cli(
        tmp_path, "version_1.0.0.txt", "commits_feat.txt"
    )
    assert result.returncode == 0, result.stderr
    assert "1.1.0" in result.stdout
    assert version_file.read_text().strip() == "1.1.0"


def test_cli_bumps_major_version_from_breaking_commit(tmp_path):
    result, version_file, changelog_file = _run_cli(
        tmp_path, "version_1.0.0.txt", "commits_breaking.txt"
    )
    assert result.returncode == 0, result.stderr
    assert "2.0.0" in result.stdout
    assert version_file.read_text().strip() == "2.0.0"


def test_cli_exits_nonzero_with_clear_message_when_no_bumpable_commits(tmp_path):
    result, version_file, changelog_file = _run_cli(
        tmp_path, "version_1.0.0.txt", "commits_none.txt"
    )
    assert result.returncode != 0
    assert "no version-bumping commits" in result.stderr.lower()
    # version file must be left untouched
    assert version_file.read_text().strip() == "1.0.0"
