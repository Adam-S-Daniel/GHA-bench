"""Red/green TDD test suite for the semantic version bumper.

The tests are grouped to mirror the order in which functionality was
built up:  version parsing -> commit parsing -> bump decision ->
changelog -> file I/O -> CLI.  Each group was written *before* the
corresponding implementation existed (red), then the minimum code was
added to make it pass (green).
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

import semver_bumper as svb


# ---------------------------------------------------------------------------
# Cycle 1 — version string parsing / formatting / arithmetic
# ---------------------------------------------------------------------------

class TestVersionParsing:
    def test_parse_simple_version(self):
        assert svb.parse_version("1.2.3") == (1, 2, 3)

    def test_parse_version_strips_whitespace_and_v_prefix(self):
        # A leading "v" and surrounding whitespace are tolerated.
        assert svb.parse_version("  v0.0.1\n") == (0, 0, 1)

    def test_format_version_roundtrip(self):
        assert svb.format_version((2, 5, 9)) == "2.5.9"

    @pytest.mark.parametrize("bad", ["1.2", "1.2.x", "abc", "", "1.2.3.4"])
    def test_parse_version_rejects_garbage(self, bad):
        # Invalid version strings must raise a clear, typed error.
        with pytest.raises(svb.SemverError):
            svb.parse_version(bad)


class TestBumpArithmetic:
    def test_major_bump_zeroes_minor_and_patch(self):
        assert svb.bump_version("1.4.2", "major") == "2.0.0"

    def test_minor_bump_zeroes_patch(self):
        assert svb.bump_version("1.4.2", "minor") == "1.5.0"

    def test_patch_bump_increments_patch(self):
        assert svb.bump_version("1.4.2", "patch") == "1.4.3"

    def test_bump_with_unknown_type_raises(self):
        with pytest.raises(svb.SemverError):
            svb.bump_version("1.0.0", "mega")


# ---------------------------------------------------------------------------
# Cycle 2 — conventional commit parsing and the bump decision
# ---------------------------------------------------------------------------

FIXTURES = Path(__file__).parent / "fixtures"


def load_fixture(name: str) -> str:
    return (FIXTURES / name).read_text()


class TestCommitParsing:
    def test_parses_type_scope_and_description(self):
        commit = svb.parse_commit("feat(api): add pagination to list endpoint")
        assert commit.type == "feat"
        assert commit.scope == "api"
        assert commit.description == "add pagination to list endpoint"
        assert commit.breaking is False

    def test_scope_is_optional(self):
        commit = svb.parse_commit("fix: avoid race condition")
        assert commit.type == "fix"
        assert commit.scope is None
        assert commit.description == "avoid race condition"

    def test_bang_marks_breaking_change(self):
        commit = svb.parse_commit("feat(api)!: drop v1 routes")
        assert commit.type == "feat"
        assert commit.breaking is True

    def test_breaking_change_footer_marks_breaking(self):
        raw = "feat: new engine\n\nBREAKING CHANGE: config format changed."
        commit = svb.parse_commit(raw)
        assert commit.breaking is True

    def test_non_conventional_commit_has_no_type(self):
        # Free-form commits are parsed but contribute no bump signal.
        commit = svb.parse_commit("merge branch 'main' into feature")
        assert commit.type is None
        assert commit.breaking is False

    def test_parse_commits_splits_on_delimiter(self):
        commits = svb.parse_commits(load_fixture("feat_commits.log"))
        assert len(commits) == 3
        assert [c.type for c in commits] == ["feat", "fix", "chore"]

    def test_parse_commits_ignores_blank_trailing_blocks(self):
        # Trailing delimiter / whitespace must not produce empty commits.
        text = "fix: a thing\n--END--\n\n--END--\n"
        commits = svb.parse_commits(text)
        assert len(commits) == 1


class TestBumpDecision:
    def test_feat_fixture_yields_minor(self):
        commits = svb.parse_commits(load_fixture("feat_commits.log"))
        assert svb.determine_bump(commits) == "minor"

    def test_fix_fixture_yields_patch(self):
        commits = svb.parse_commits(load_fixture("fix_commits.log"))
        assert svb.determine_bump(commits) == "patch"

    def test_breaking_fixture_yields_major(self):
        commits = svb.parse_commits(load_fixture("breaking_commits.log"))
        assert svb.determine_bump(commits) == "major"

    def test_no_relevant_commits_yields_none(self):
        commits = svb.parse_commits(load_fixture("no_bump_commits.log"))
        assert svb.determine_bump(commits) is None

    def test_empty_commit_list_yields_none(self):
        assert svb.determine_bump([]) is None

    def test_breaking_takes_priority_over_feat_and_fix(self):
        commits = svb.parse_commits(load_fixture("mixed_commits.log"))
        assert svb.determine_bump(commits) == "major"


# ---------------------------------------------------------------------------
# Cycle 3a — changelog generation
# ---------------------------------------------------------------------------

class TestChangelog:
    def test_changelog_has_versioned_header_with_date(self):
        commits = svb.parse_commits(load_fixture("feat_commits.log"))
        entry = svb.generate_changelog(commits, "1.2.0", "2026-06-27")
        assert "## [1.2.0] - 2026-06-27" in entry

    def test_changelog_groups_features_and_fixes(self):
        commits = svb.parse_commits(load_fixture("mixed_commits.log"))
        entry = svb.generate_changelog(commits, "2.0.0", "2026-06-27")
        assert "### Features" in entry
        assert "### Bug Fixes" in entry
        # scoped vs unscoped rendering
        assert "- **ui**: add dark mode toggle" in entry
        assert "- support YAML config files" in entry

    def test_changelog_lists_breaking_changes_section(self):
        commits = svb.parse_commits(load_fixture("mixed_commits.log"))
        entry = svb.generate_changelog(commits, "2.0.0", "2026-06-27")
        assert "### BREAKING CHANGES" in entry
        assert "rename init() to setup()" in entry

    def test_changelog_omits_empty_sections(self):
        commits = svb.parse_commits(load_fixture("fix_commits.log"))
        entry = svb.generate_changelog(commits, "1.1.1", "2026-06-27")
        assert "### Bug Fixes" in entry
        assert "### Features" not in entry
        assert "### BREAKING CHANGES" not in entry


# ---------------------------------------------------------------------------
# Cycle 3b — version-file and changelog-file I/O
# ---------------------------------------------------------------------------

class TestVersionFileIO:
    def test_read_plain_version_file(self, tmp_path):
        vf = tmp_path / "VERSION"
        vf.write_text("1.1.0\n")
        assert svb.read_version_file(vf) == "1.1.0"

    def test_read_version_from_package_json(self, tmp_path):
        pj = tmp_path / "package.json"
        pj.write_text(json.dumps({"name": "demo", "version": "3.4.5"}))
        assert svb.read_version_file(pj) == "3.4.5"

    def test_read_missing_file_raises(self, tmp_path):
        with pytest.raises(svb.SemverError):
            svb.read_version_file(tmp_path / "nope")

    def test_read_package_json_without_version_raises(self, tmp_path):
        pj = tmp_path / "package.json"
        pj.write_text(json.dumps({"name": "demo"}))
        with pytest.raises(svb.SemverError):
            svb.read_version_file(pj)

    def test_write_plain_version_file(self, tmp_path):
        vf = tmp_path / "VERSION"
        svb.write_version_file(vf, "2.0.0")
        assert vf.read_text().strip() == "2.0.0"

    def test_write_package_json_preserves_other_keys(self, tmp_path):
        pj = tmp_path / "package.json"
        pj.write_text(json.dumps({"name": "demo", "version": "1.0.0", "private": True}))
        svb.write_version_file(pj, "1.1.0")
        data = json.loads(pj.read_text())
        assert data["version"] == "1.1.0"
        assert data["name"] == "demo"        # untouched
        assert data["private"] is True       # untouched


class TestChangelogFile:
    def test_prepend_creates_file_with_title(self, tmp_path):
        cl = tmp_path / "CHANGELOG.md"
        svb.prepend_changelog(cl, "## [1.0.0] - 2026-06-27\n\n### Features\n- thing")
        text = cl.read_text()
        assert text.startswith("# Changelog")
        assert "## [1.0.0]" in text

    def test_prepend_puts_newest_entry_first(self, tmp_path):
        cl = tmp_path / "CHANGELOG.md"
        svb.prepend_changelog(cl, "## [1.0.0] - 2026-06-27\n\n### Features\n- old")
        svb.prepend_changelog(cl, "## [1.1.0] - 2026-06-28\n\n### Features\n- new")
        text = cl.read_text()
        # Title appears exactly once and the newer version precedes the older.
        assert text.count("# Changelog\n") == 1
        assert text.index("## [1.1.0]") < text.index("## [1.0.0]")


# ---------------------------------------------------------------------------
# Cycle 3c — the end-to-end CLI (`main`)
# ---------------------------------------------------------------------------

class TestMainCLI:
    def _run(self, args, capsys):
        code = svb.main(args)
        out = capsys.readouterr()
        return code, out.out, out.err

    def test_main_bumps_minor_for_feat_and_writes_files(self, tmp_path, capsys):
        vf = tmp_path / "VERSION"
        vf.write_text("1.1.0\n")
        cf = tmp_path / "commits.log"
        cf.write_text(load_fixture("feat_commits.log"))
        cl = tmp_path / "CHANGELOG.md"

        code, out, _ = self._run(
            ["--version-file", str(vf), "--commits-file", str(cf),
             "--changelog", str(cl), "--date", "2026-06-27"],
            capsys,
        )
        assert code == 0
        assert "NEW_VERSION=1.2.0" in out
        assert "BUMP_TYPE=minor" in out
        assert vf.read_text().strip() == "1.2.0"
        assert "## [1.2.0] - 2026-06-27" in cl.read_text()

    def test_main_major_for_breaking(self, tmp_path, capsys):
        vf = tmp_path / "VERSION"
        vf.write_text("1.1.0\n")
        cf = tmp_path / "commits.log"
        cf.write_text(load_fixture("breaking_commits.log"))
        code, out, _ = self._run(
            ["--version-file", str(vf), "--commits-file", str(cf),
             "--changelog", str(tmp_path / "CHANGELOG.md"), "--date", "2026-06-27"],
            capsys,
        )
        assert code == 0
        assert "NEW_VERSION=2.0.0" in out

    def test_main_no_bump_leaves_version_untouched(self, tmp_path, capsys):
        vf = tmp_path / "VERSION"
        vf.write_text("1.1.0\n")
        cf = tmp_path / "commits.log"
        cf.write_text(load_fixture("no_bump_commits.log"))
        code, out, _ = self._run(
            ["--version-file", str(vf), "--commits-file", str(cf),
             "--changelog", str(tmp_path / "CHANGELOG.md"), "--date", "2026-06-27"],
            capsys,
        )
        assert code == 0
        assert "BUMP_TYPE=none" in out
        assert "NEW_VERSION=1.1.0" in out          # unchanged
        assert vf.read_text().strip() == "1.1.0"   # file not modified

    def test_main_dry_run_does_not_write(self, tmp_path, capsys):
        vf = tmp_path / "VERSION"
        vf.write_text("1.1.0\n")
        cf = tmp_path / "commits.log"
        cf.write_text(load_fixture("fix_commits.log"))
        cl = tmp_path / "CHANGELOG.md"
        code, out, _ = self._run(
            ["--version-file", str(vf), "--commits-file", str(cf),
             "--changelog", str(cl), "--date", "2026-06-27", "--dry-run"],
            capsys,
        )
        assert code == 0
        assert "NEW_VERSION=1.1.1" in out
        assert vf.read_text().strip() == "1.1.0"   # unchanged on dry-run
        assert not cl.exists()                     # no changelog written

    def test_main_errors_on_missing_version_file(self, tmp_path, capsys):
        cf = tmp_path / "commits.log"
        cf.write_text("fix: x\n")
        code, _, err = self._run(
            ["--version-file", str(tmp_path / "MISSING"),
             "--commits-file", str(cf)],
            capsys,
        )
        assert code != 0
        assert "MISSING" in err or "not found" in err.lower()

    def test_main_reads_commits_from_real_git_range(self, tmp_path, capsys):
        # Exercises the real `git log` code path used in production CI.
        repo = tmp_path / "repo"
        repo.mkdir()
        env = ["-c", "user.email=test@example.com", "-c", "user.name=Tester"]
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        for msg in ["chore: scaffold project",
                    "feat(core): add the thing",
                    "fix: tidy edge case"]:
            subprocess.run(["git", *env, "commit", "--allow-empty", "-q", "-m", msg],
                           cwd=repo, check=True)
        vf = repo / "VERSION"
        vf.write_text("1.0.0\n")
        code, out, _ = self._run(
            ["--version-file", str(vf), "--git-range", "HEAD",
             "--repo", str(repo),
             "--changelog", str(repo / "CHANGELOG.md"), "--date", "2026-06-27"],
            capsys,
        )
        assert code == 0
        assert "NEW_VERSION=1.1.0" in out          # feat -> minor
