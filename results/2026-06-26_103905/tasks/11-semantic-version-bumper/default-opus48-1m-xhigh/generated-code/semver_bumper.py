#!/usr/bin/env python3
"""Semantic version bumper driven by conventional commits.

Approach
--------
Given a current semantic version (read from a plain ``VERSION`` file or a
``package.json``) and a log of conventional-commit messages, this tool:

1. Decides the next version using the conventional-commits rules
   (``feat`` -> minor, ``fix`` -> patch, a breaking change -> major).
2. Writes the bumped version back to the version file.
3. Prepends a grouped changelog entry to ``CHANGELOG.md``.
4. Prints the new version (plus machine-readable ``KEY=VALUE`` lines that
   the GitHub Actions workflow parses).

This first section only implements version-string parsing and arithmetic
(the first red/green TDD cycle).  Later cycles add commit parsing, the
bump decision, changelog generation, file I/O and the CLI.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

# A version is exactly three dot-separated, non-negative integers.  A
# leading ``v`` and surrounding whitespace are tolerated for convenience.
_VERSION_RE = re.compile(r"^\s*v?(\d+)\.(\d+)\.(\d+)\s*$")

# Conventional-commit header:  type(scope)!: description
#   - type: a word such as feat, fix, chore, docs, ...
#   - (scope): optional, anything but ')'
#   - !: optional breaking-change marker
_HEADER_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)"          # commit type
    r"(?:\((?P<scope>[^)]+)\))?"     # optional (scope)
    r"(?P<bang>!)?"                   # optional breaking '!'
    r":\s*(?P<desc>.+)$"             # ': ' then the description
)

# A "BREAKING CHANGE:" (or "BREAKING-CHANGE:") footer also forces a major bump.
_BREAKING_FOOTER_RE = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)

# Delimiter used to separate individual commits in a log file.  It is
# emitted by ``git log --pretty=format:'%B%n--END--'`` and is also what the
# test fixtures use, so the same parser handles real and mock input.
COMMIT_DELIMITER = "--END--"


class SemverError(Exception):
    """Raised for any user-facing error (bad version, unknown bump, ...).

    Using a dedicated exception type lets the CLI catch *our* errors and
    print a clean message while letting genuine bugs surface as tracebacks.
    """


def parse_version(version_str: str) -> tuple[int, int, int]:
    """Parse ``"MAJOR.MINOR.PATCH"`` into an ``(int, int, int)`` tuple.

    Raises ``SemverError`` with a helpful message for anything that is not
    a valid three-component semantic version.
    """
    if not isinstance(version_str, str):
        raise SemverError(f"version must be a string, got {type(version_str).__name__}")
    match = _VERSION_RE.match(version_str)
    if not match:
        raise SemverError(
            f"invalid semantic version: {version_str!r} "
            "(expected MAJOR.MINOR.PATCH, e.g. 1.4.2)"
        )
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def format_version(version: tuple[int, int, int]) -> str:
    """Render a ``(major, minor, patch)`` tuple back to a string."""
    return ".".join(str(part) for part in version)


def bump_version(version_str: str, bump_type: str) -> str:
    """Return the next version string given a bump type.

    * ``major`` -> increment major, reset minor and patch to 0
    * ``minor`` -> increment minor, reset patch to 0
    * ``patch`` -> increment patch
    """
    major, minor, patch = parse_version(version_str)
    if bump_type == "major":
        return format_version((major + 1, 0, 0))
    if bump_type == "minor":
        return format_version((major, minor + 1, 0))
    if bump_type == "patch":
        return format_version((major, minor, patch + 1))
    raise SemverError(
        f"unknown bump type: {bump_type!r} (expected 'major', 'minor' or 'patch')"
    )


# ---------------------------------------------------------------------------
# Conventional-commit parsing
# ---------------------------------------------------------------------------

@dataclass
class Commit:
    """A parsed commit message.

    ``type`` is ``None`` for non-conventional commits (e.g. merge commits);
    these contribute no bump signal but are still kept so the caller can
    count or display them if desired.
    """

    type: str | None
    scope: str | None
    breaking: bool
    description: str
    raw: str


def parse_commit(raw: str) -> Commit:
    """Parse a single (possibly multi-line) commit message.

    The first non-empty line is treated as the conventional-commit header;
    the remaining lines form the body, which is scanned for a
    ``BREAKING CHANGE:`` footer.
    """
    raw = raw.strip()
    lines = raw.splitlines()
    header = lines[0].strip() if lines else ""
    body = "\n".join(lines[1:])

    match = _HEADER_RE.match(header)
    breaking = bool(_BREAKING_FOOTER_RE.search(raw))

    if not match:
        # Not a conventional commit: no type, but a footer could still flag
        # it as breaking.
        return Commit(type=None, scope=None, breaking=breaking,
                      description=header, raw=raw)

    breaking = breaking or bool(match.group("bang"))
    return Commit(
        type=match.group("type").lower(),
        scope=match.group("scope"),
        breaking=breaking,
        description=match.group("desc").strip(),
        raw=raw,
    )


def parse_commits(log_text: str) -> list[Commit]:
    """Split a delimited commit log into a list of :class:`Commit`.

    Blocks that are empty after stripping (e.g. a trailing delimiter) are
    skipped so they do not masquerade as real commits.
    """
    blocks = log_text.split(COMMIT_DELIMITER)
    return [parse_commit(block) for block in blocks if block.strip()]


# ---------------------------------------------------------------------------
# Bump decision
# ---------------------------------------------------------------------------

def determine_bump(commits: list[Commit]) -> str | None:
    """Return ``'major'``, ``'minor'``, ``'patch'`` or ``None``.

    Precedence follows the conventional-commits spec: any breaking change
    forces a major bump, otherwise any ``feat`` forces a minor bump,
    otherwise any ``fix`` forces a patch bump.  If nothing relevant is
    present we return ``None`` to signal "no release needed".
    """
    if any(commit.breaking for commit in commits):
        return "major"
    if any(commit.type == "feat" for commit in commits):
        return "minor"
    if any(commit.type == "fix" for commit in commits):
        return "patch"
    return None


# ---------------------------------------------------------------------------
# Changelog generation
# ---------------------------------------------------------------------------

# Commit types that earn their own changelog section, in display order.
# Types not listed (chore, docs, ci, ...) are intentionally omitted from the
# changelog, mirroring common "keep a changelog" practice.
_CHANGELOG_SECTIONS = [
    ("feat", "Features"),
    ("fix", "Bug Fixes"),
    ("perf", "Performance Improvements"),
]


def _render_item(commit: Commit) -> str:
    """Render one commit as a markdown bullet, prefixing the scope if any."""
    if commit.scope:
        return f"- **{commit.scope}**: {commit.description}"
    return f"- {commit.description}"


def generate_changelog(commits: list[Commit], new_version: str, date: str) -> str:
    """Build a single changelog entry (markdown) for ``new_version``.

    Breaking changes are listed first under their own heading, followed by
    Features / Bug Fixes / Performance sections.  Empty sections are
    omitted entirely so the entry stays tidy.
    """
    lines = [f"## [{new_version}] - {date}", ""]

    breaking = [c for c in commits if c.breaking]
    if breaking:
        lines.append("### BREAKING CHANGES")
        lines.extend(_render_item(c) for c in breaking)
        lines.append("")

    for commit_type, heading in _CHANGELOG_SECTIONS:
        matching = [c for c in commits if c.type == commit_type]
        if not matching:
            continue
        lines.append(f"### {heading}")
        lines.extend(_render_item(c) for c in matching)
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


# ---------------------------------------------------------------------------
# Version-file and changelog-file I/O
# ---------------------------------------------------------------------------

def read_version_file(path) -> str:
    """Read the current version from a ``VERSION`` file or ``package.json``.

    ``*.json`` files are parsed and the ``version`` key returned; any other
    file is treated as plain text containing only the version string.
    """
    p = Path(path)
    if not p.exists():
        raise SemverError(f"version file not found: {p}")

    if p.suffix == ".json":
        try:
            data = json.loads(p.read_text())
        except json.JSONDecodeError as exc:
            raise SemverError(f"could not parse JSON in {p}: {exc}") from exc
        if "version" not in data:
            raise SemverError(f"no 'version' key in {p}")
        return str(data["version"]).strip()

    return p.read_text().strip()


def write_version_file(path, new_version: str) -> None:
    """Write ``new_version`` back, preserving JSON structure where relevant."""
    p = Path(path)
    if p.suffix == ".json":
        # Preserve every other key and the 2-space indentation npm uses.
        data = json.loads(p.read_text()) if p.exists() else {}
        data["version"] = new_version
        p.write_text(json.dumps(data, indent=2) + "\n")
    else:
        p.write_text(new_version + "\n")


_CHANGELOG_TITLE = "# Changelog"


def prepend_changelog(path, entry: str) -> None:
    """Insert ``entry`` directly below the ``# Changelog`` title.

    The newest entry therefore always appears first.  The title is created
    on first use and never duplicated.
    """
    p = Path(path)
    entry = entry.strip() + "\n"

    if not p.exists():
        p.write_text(f"{_CHANGELOG_TITLE}\n\n{entry}")
        return

    content = p.read_text()
    if content.lstrip().startswith(_CHANGELOG_TITLE):
        # Drop the existing title + leading blank lines, then rebuild so the
        # title stays unique and the new entry sits at the top.
        body = content.lstrip()[len(_CHANGELOG_TITLE):].lstrip("\n")
        p.write_text(f"{_CHANGELOG_TITLE}\n\n{entry}\n{body}")
    else:
        p.write_text(f"{_CHANGELOG_TITLE}\n\n{entry}\n{content}")


# ---------------------------------------------------------------------------
# Reading commits from a real git repository
# ---------------------------------------------------------------------------

def read_commits_from_git(git_range: str, repo: str = ".") -> str:
    """Return a delimited commit log for ``git_range`` via ``git log``.

    The ``%B%n--END--`` format yields exactly the delimiter-separated layout
    that :func:`parse_commits` (and the fixtures) understand, so production
    and test input share one parser.
    """
    cmd = [
        "git", "-C", repo, "log",
        f"--pretty=format:%B%n{COMMIT_DELIMITER}",
        git_range,
    ]
    try:
        result = subprocess.run(
            cmd, check=True, capture_output=True, text=True
        )
    except FileNotFoundError as exc:  # git not installed
        raise SemverError("git executable not found on PATH") from exc
    except subprocess.CalledProcessError as exc:
        raise SemverError(
            f"git log failed for range {git_range!r}: {exc.stderr.strip()}"
        ) from exc
    return result.stdout


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------

def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="semver_bumper",
        description="Bump a semantic version from conventional commit messages.",
    )
    parser.add_argument(
        "--version-file", default="VERSION",
        help="path to the version file (VERSION or package.json). Default: VERSION",
    )
    parser.add_argument(
        "--changelog", default="CHANGELOG.md",
        help="path to the changelog file to update. Default: CHANGELOG.md",
    )
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--commits-file",
        help="read commit messages from this delimited log file",
    )
    source.add_argument(
        "--git-range",
        help="read commits from `git log` for this range (e.g. v1.0.0..HEAD)",
    )
    parser.add_argument(
        "--repo", default=".",
        help="repository directory for --git-range. Default: current directory",
    )
    parser.add_argument(
        "--date", default=None,
        help="date for the changelog entry (YYYY-MM-DD). Default: today (UTC)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="compute and print the next version without writing any files",
    )
    return parser


def _load_commits(args) -> list[Commit]:
    """Resolve the commit source (file or git) into parsed commits."""
    if args.commits_file:
        path = Path(args.commits_file)
        if not path.exists():
            raise SemverError(f"commits file not found: {path}")
        return parse_commits(path.read_text())
    if args.git_range:
        return parse_commits(read_commits_from_git(args.git_range, args.repo))
    raise SemverError("you must provide either --commits-file or --git-range")


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.  Returns a process exit code (0 on success)."""
    args = _build_arg_parser().parse_args(argv)

    try:
        current_version = read_version_file(args.version_file)
        # Validate early so a malformed version file fails loudly.
        parse_version(current_version)

        commits = _load_commits(args)
        bump_type = determine_bump(commits)

        if bump_type is None:
            # Nothing release-worthy: report and leave every file untouched.
            print(f"PREVIOUS_VERSION={current_version}")
            print("BUMP_TYPE=none")
            print(f"NEW_VERSION={current_version}")
            print("No feat/fix/breaking commits found; version unchanged.",
                  file=sys.stderr)
            return 0

        new_version = bump_version(current_version, bump_type)
        date = args.date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
        entry = generate_changelog(commits, new_version, date)

        if not args.dry_run:
            write_version_file(args.version_file, new_version)
            prepend_changelog(args.changelog, entry)

        # Machine-readable contract consumed by the GitHub Actions workflow.
        print(f"PREVIOUS_VERSION={current_version}")
        print(f"BUMP_TYPE={bump_type}")
        print(f"NEW_VERSION={new_version}")
        return 0

    except SemverError as exc:
        # Expected, user-facing failure: clean message, no traceback.
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
