#!/usr/bin/env python3
"""Semantic version bumper driven by conventional commit messages.

Built incrementally with red/green TDD. Each public function below was added
only after a failing test demanded it. See tests/ for the specification.
"""
import json
import os
import re
import sys

# Matches a conventional-commit subject: "type(optional scope)!: description".
# We only need the type and the optional breaking "!" marker here.
_HEADER_RE = re.compile(r"^(?P<type>[a-zA-Z]+)(?:\([^)]*\))?(?P<bang>!)?:")

# Numeric ranking so we can pick the strongest bump across many commits.
_RANK = {"patch": 1, "minor": 2, "major": 3}


def read_version(path):
    """Return the semantic version string stored in `path`.

    Supports two file conventions:
      * package.json  -> read the top-level "version" key
      * anything else -> treat the whole file as the bare version string

    Raises FileNotFoundError with a friendly message when the file is absent.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Version file not found: {path}")

    if os.path.basename(path) == "package.json":
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if "version" not in data:
            raise ValueError(f"No 'version' key in {path}")
        return str(data["version"]).strip()

    with open(path, encoding="utf-8") as fh:
        return fh.read().strip()


def _classify(commit_message):
    """Return the bump level a single commit implies, or None.

    A "BREAKING CHANGE" footer or a "!" before the colon always means major.
    Otherwise feat -> minor, fix -> patch, everything else -> None.
    """
    # A breaking-change footer can appear on any line of the body.
    if "BREAKING CHANGE" in commit_message:
        return "major"

    header = commit_message.splitlines()[0] if commit_message else ""
    match = _HEADER_RE.match(header.strip())
    if not match:
        return None

    if match.group("bang"):
        return "major"

    ctype = match.group("type").lower()
    if ctype == "feat":
        return "minor"
    if ctype == "fix":
        return "patch"
    return None


def determine_bump(commits):
    """Return the highest-precedence bump ('major'/'minor'/'patch') for a list
    of commit messages, or None when no commit warrants a release.
    """
    best = None
    best_rank = 0
    for commit in commits:
        level = _classify(commit)
        if level and _RANK[level] > best_rank:
            best, best_rank = level, _RANK[level]
    return best


def next_version(version, bump_type):
    """Compute the next semantic version given a bump type.

    Pre-release/build metadata is intentionally out of scope; we expect a clean
    MAJOR.MINOR.PATCH string and raise a clear error otherwise.
    """
    parts = version.strip().lstrip("v").split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError(f"Invalid semantic version: {version!r}")
    major, minor, patch = (int(p) for p in parts)

    if bump_type == "major":
        return f"{major + 1}.0.0"
    if bump_type == "minor":
        return f"{major}.{minor + 1}.0"
    if bump_type == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ValueError(f"Unknown bump type: {bump_type!r}")


def parse_commit_log(path):
    """Read a NUL-delimited commit log fixture into a list of messages.

    Using a NUL separator (matching `git log -z`) lets commit bodies span
    multiple lines without ambiguity. Blank records are dropped.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Commit log not found: {path}")
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    return [rec.strip() for rec in raw.split("\x00") if rec.strip()]


def _describe(commit_message):
    """Strip the conventional-commit prefix, returning the human description."""
    header = commit_message.splitlines()[0].strip()
    # Remove everything up to and including the first ": ".
    if ":" in header:
        return header.split(":", 1)[1].strip()
    return header


def generate_changelog(version, commits, date):
    """Render a Markdown changelog entry grouped by change category.

    Commits that aren't feat/fix/breaking are omitted from the changelog.
    """
    breaking, features, fixes = [], [], []
    for commit in commits:
        level = _classify(commit)
        desc = _describe(commit)
        if level == "major":
            breaking.append(desc)
        elif level == "minor":
            features.append(desc)
        elif level == "patch":
            fixes.append(desc)

    lines = [f"## {version} - {date}", ""]
    for title, items in (
        ("Breaking Changes", breaking),
        ("Features", features),
        ("Fixes", fixes),
    ):
        if items:
            lines.append(f"### {title}")
            lines.extend(f"- {item}" for item in items)
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def update_version_file(path, new_version):
    """Write `new_version` back to the version file, in place.

    For package.json we rewrite only the "version" key and keep the rest of
    the document (and a trailing newline) intact.
    """
    if os.path.basename(path) == "package.json":
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        data["version"] = new_version
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    else:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_version + "\n")


def _prepend_changelog(path, entry):
    """Prepend a new changelog entry under the file's top heading.

    Keeps a leading "# Changelog" title if present; otherwise creates one.
    """
    header = "# Changelog\n\n"
    existing = ""
    if os.path.exists(path):
        existing = open(path, encoding="utf-8").read()
        if existing.startswith("# Changelog"):
            # Split the title line off so new entries sit directly beneath it.
            _, _, existing = existing.partition("\n")
            existing = existing.lstrip("\n")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(header + entry + ("\n" + existing if existing else ""))


def main(argv=None):
    """CLI entrypoint: read version + commits, bump, write files, report.

    Exit code is 0 on success (including the "no release needed" case) and 1
    on any handled error, with a meaningful message on stderr.
    """
    import argparse

    parser = argparse.ArgumentParser(description="Semantic version bumper.")
    parser.add_argument("--version-file", required=True,
                        help="Path to VERSION file or package.json.")
    parser.add_argument("--commits", required=True,
                        help="Path to a NUL-delimited commit log fixture.")
    parser.add_argument("--changelog", default="CHANGELOG.md",
                        help="Changelog file to prepend the new entry to.")
    parser.add_argument("--date", default=None,
                        help="Release date (YYYY-MM-DD); defaults to today.")
    opts = parser.parse_args(argv)

    if opts.date is None:
        from datetime import date as _date
        opts.date = _date.today().isoformat()

    try:
        current = read_version(opts.version_file)
        commits = parse_commit_log(opts.commits)
        bump = determine_bump(commits)

        if bump is None:
            # Nothing release-worthy: leave files untouched, report current.
            print(f"Current version: {current}")
            print("No release needed (no feat/fix/breaking commits).")
            print(f"NEW_VERSION={current}")
            _write_github_output(current, bumped=False)
            return 0

        new = next_version(current, bump)
        update_version_file(opts.version_file, new)
        entry = generate_changelog(new, commits, opts.date)
        _prepend_changelog(opts.changelog, entry)

        print(f"Current version: {current}")
        print(f"Bump type: {bump}")
        print(f"New version: {new}")
        print(f"NEW_VERSION={new}")
        _write_github_output(new, bumped=True)
        return 0
    except (FileNotFoundError, ValueError) as err:
        print(f"Error: {err}", file=sys.stderr)
        return 1


def _write_github_output(version, bumped):
    """Expose results as GitHub Actions step outputs when running in CI."""
    gh_out = os.environ.get("GITHUB_OUTPUT")
    if not gh_out:
        return
    with open(gh_out, "a", encoding="utf-8") as fh:
        fh.write(f"new_version={version}\n")
        fh.write(f"bumped={'true' if bumped else 'false'}\n")


if __name__ == "__main__":
    sys.exit(main())
