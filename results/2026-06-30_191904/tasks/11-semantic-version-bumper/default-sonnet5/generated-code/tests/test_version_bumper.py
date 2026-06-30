"""
Unit tests for the pure logic in version_bumper.py (semantic version
calculation from Conventional Commit messages).

These are written TDD-style: each test is added *before* the corresponding
implementation exists in version_bumper.py, run once to confirm it fails
(red), then the minimum code is added to version_bumper.py to make it pass
(green). File-system / CLI integration is intentionally NOT covered here --
per the task's GitHub Actions requirement, that surface is exercised only
through the real workflow via `act` (see tests/test_workflow_via_act.py).
"""
import pytest

from version_bumper import (
    VersionBumperError,
    bump_version,
    classify_bump,
    parse_commits,
    parse_version,
    render_changelog_entry,
)


# ---------------------------------------------------------------------------
# parse_version
# ---------------------------------------------------------------------------

class TestParseVersion:
    def test_parses_simple_version(self):
        assert parse_version("1.2.3") == (1, 2, 3)

    def test_parses_version_with_leading_v(self):
        assert parse_version("v1.2.3") == (1, 2, 3)

    def test_strips_surrounding_whitespace(self):
        assert parse_version("  2.0.10\n") == (2, 0, 10)

    def test_rejects_malformed_version(self):
        with pytest.raises(VersionBumperError):
            parse_version("not-a-version")

    def test_rejects_incomplete_version(self):
        with pytest.raises(VersionBumperError):
            parse_version("1.2")


# ---------------------------------------------------------------------------
# parse_commits -- turns mock commit-log text into structured Commit objects
# ---------------------------------------------------------------------------

class TestParseCommits:
    def test_parses_feat_commit_with_sha_and_scope(self):
        commits = parse_commits("a1b2c3d feat(auth): add OAuth2 login support\n")
        assert len(commits) == 1
        c = commits[0]
        assert c.sha == "a1b2c3d"
        assert c.type == "feat"
        assert c.scope == "auth"
        assert c.breaking is False
        assert c.subject == "add OAuth2 login support"

    def test_parses_fix_commit_without_sha(self):
        commits = parse_commits("fix: correct null pointer in handler\n")
        assert len(commits) == 1
        assert commits[0].type == "fix"
        assert commits[0].sha == ""

    def test_parses_breaking_via_bang(self):
        commits = parse_commits("e4f5061 feat!: drop support for Node 12\n")
        assert commits[0].breaking is True
        assert commits[0].type == "feat"

    def test_parses_breaking_via_footer_line(self):
        commits = parse_commits(
            "1a2b3c4 refactor: rework storage layer\n"
            "BREAKING CHANGE: storage format changed, migration required\n"
        )
        assert len(commits) == 2
        assert commits[0].breaking is False
        assert commits[1].breaking is True

    def test_skips_blank_lines(self):
        commits = parse_commits("feat: a\n\n\nfix: b\n")
        assert len(commits) == 2

    def test_skips_non_conventional_lines(self):
        commits = parse_commits("Merge branch 'main' into feature\nfeat: real change\n")
        assert len(commits) == 1
        assert commits[0].subject == "real change"


# ---------------------------------------------------------------------------
# classify_bump -- precedence: breaking > feat > fix > none
# ---------------------------------------------------------------------------

class TestClassifyBump:
    def test_breaking_wins_over_feat_and_fix(self):
        commits = parse_commits("feat: a\nfix: b\nfeat!: c\n")
        assert classify_bump(commits) == "major"

    def test_feat_wins_over_fix(self):
        commits = parse_commits("fix: a\nfeat: b\n")
        assert classify_bump(commits) == "minor"

    def test_fix_alone_yields_patch(self):
        commits = parse_commits("fix: a\n")
        assert classify_bump(commits) == "patch"

    def test_no_relevant_commits_yields_none(self):
        commits = parse_commits("docs: update README\nchore: bump deps\n")
        assert classify_bump(commits) is None

    def test_empty_commit_list_yields_none(self):
        assert classify_bump([]) is None


# ---------------------------------------------------------------------------
# bump_version -- pure semver arithmetic
# ---------------------------------------------------------------------------

class TestBumpVersion:
    def test_major_bump_resets_minor_and_patch(self):
        assert bump_version((1, 4, 7), "major") == (2, 0, 0)

    def test_minor_bump_resets_patch(self):
        assert bump_version((1, 4, 7), "minor") == (1, 5, 0)

    def test_patch_bump_increments_patch_only(self):
        assert bump_version((1, 4, 7), "patch") == (1, 4, 8)

    def test_unknown_bump_type_raises(self):
        with pytest.raises(VersionBumperError):
            bump_version((1, 0, 0), "banana")


# ---------------------------------------------------------------------------
# render_changelog_entry -- groups commits under Breaking/Added/Fixed/Other
# ---------------------------------------------------------------------------

class TestRenderChangelogEntry:
    def test_includes_version_heading_with_date(self):
        commits = parse_commits("feat: add widgets\n")
        entry = render_changelog_entry("1.1.0", commits, "2026-01-15")
        assert entry.startswith("## [1.1.0] - 2026-01-15\n")

    def test_groups_feat_under_added(self):
        commits = parse_commits("a1b2c3d feat: add widgets\n")
        entry = render_changelog_entry("1.1.0", commits, "2026-01-15")
        assert "### Added" in entry
        assert "- add widgets (a1b2c3d)" in entry

    def test_groups_fix_under_fixed(self):
        commits = parse_commits("fix: stop crash\n")
        entry = render_changelog_entry("1.0.1", commits, "2026-01-15")
        assert "### Fixed" in entry
        assert "- stop crash" in entry

    def test_groups_breaking_under_breaking_changes(self):
        commits = parse_commits("feat!: remove legacy API\n")
        entry = render_changelog_entry("2.0.0", commits, "2026-01-15")
        assert "### Breaking Changes" in entry
        assert "- remove legacy API" in entry

    def test_omits_empty_sections(self):
        commits = parse_commits("fix: a\n")
        entry = render_changelog_entry("1.0.1", commits, "2026-01-15")
        assert "### Added" not in entry
        assert "### Breaking Changes" not in entry
