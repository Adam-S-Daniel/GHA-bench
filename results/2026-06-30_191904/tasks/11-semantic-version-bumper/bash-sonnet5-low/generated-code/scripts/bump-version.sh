#!/usr/bin/env bash
# bump-version.sh
#
# Reads a semantic version from a version file (plain text or package.json),
# inspects a file of conventional-commit-style messages to decide whether
# the next version is a major/minor/patch bump, writes the new version back
# to the version file, prepends a changelog entry, and prints the new
# version to stdout.
set -euo pipefail

VERSION_FILE=""
COMMITS_FILE=""
CHANGELOG_FILE="CHANGELOG.md"

usage() {
  echo "Usage: $0 --version-file FILE --commits-file FILE [--changelog-file FILE]" >&2
}

die() {
  echo "Error: $1" >&2
  exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --version-file)
        VERSION_FILE="$2"
        shift 2
        ;;
      --commits-file)
        COMMITS_FILE="$2"
        shift 2
        ;;
      --changelog-file)
        CHANGELOG_FILE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  [ -n "$VERSION_FILE" ] || { usage; die "--version-file is required"; }
  [ -n "$COMMITS_FILE" ] || { usage; die "--commits-file is required"; }
}

# Detects whether the version file is a package.json (JSON) or a plain
# text file containing just the version string.
detect_format() {
  local file="$1"
  case "$file" in
    *.json) echo "json" ;;
    *) echo "plain" ;;
  esac
}

# Reads the current semver out of the version file, regardless of format.
read_version() {
  local file="$1" format="$2" raw
  if [ "$format" = "json" ]; then
    raw="$(grep -m1 '"version"[[:space:]]*:' "$file" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  else
    raw="$(tr -d '[:space:]' < "$file")"
  fi
  echo "$raw"
}

# Validates that a string is a bare MAJOR.MINOR.PATCH semver (no pre-release
# or build metadata, which this tool does not need to support).
validate_semver() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid semantic version: '$version'"
}

# Scans the commits file for conventional-commit prefixes and returns the
# highest-precedence bump type found: major, minor, patch, or none.
determine_bump() {
  local commits_file="$1"
  local bump="none"

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == *"BREAKING CHANGE"* ]] || [[ "$line" =~ ^[a-zA-Z]+(\([^\)]*\))?\! ]]; then
      bump="major"
    elif [[ "$bump" != "major" ]] && [[ "$line" =~ ^feat(\([^\)]*\))?: ]]; then
      bump="minor"
    elif [[ "$bump" != "major" && "$bump" != "minor" ]] && [[ "$line" =~ ^fix(\([^\)]*\))?: ]]; then
      bump="patch"
    fi
  done < "$commits_file"

  echo "$bump"
}

# Computes the next version given a current version and a bump type.
next_version() {
  local version="$1" bump="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"

  case "$bump" in
    major)
      echo "$((major + 1)).0.0"
      ;;
    minor)
      echo "${major}.$((minor + 1)).0"
      ;;
    patch)
      echo "${major}.${minor}.$((patch + 1))"
      ;;
    *)
      die "no bumpable commits found (no feat/fix/BREAKING CHANGE prefixes)"
      ;;
  esac
}

# Writes the new version back into the version file, preserving format.
write_version() {
  local file="$1" format="$2" new_version="$3"
  if [ "$format" = "json" ]; then
    local tmp
    tmp="$(mktemp)"
    sed -E "s/(\"version\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"${new_version}\"/" "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s' "$new_version" > "$file"
  fi
}

# Prepends a "## <new_version>" changelog section, listing each commit
# subject as a bullet, above any existing changelog content.
write_changelog() {
  local changelog_file="$1" new_version="$2" commits_file="$3"
  local tmp
  tmp="$(mktemp)"

  {
    echo "## ${new_version}"
    echo
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && echo "- ${line}"
    done < "$commits_file"
    echo
    if [ -f "$changelog_file" ]; then
      cat "$changelog_file"
    fi
  } > "$tmp"

  mv "$tmp" "$changelog_file"
}

main() {
  parse_args "$@"

  [ -f "$VERSION_FILE" ] || die "version file not found: $VERSION_FILE"
  [ -f "$COMMITS_FILE" ] || die "commits file not found: $COMMITS_FILE"

  local format current_version bump new_version
  format="$(detect_format "$VERSION_FILE")"
  current_version="$(read_version "$VERSION_FILE" "$format")"
  validate_semver "$current_version"

  bump="$(determine_bump "$COMMITS_FILE")"
  new_version="$(next_version "$current_version" "$bump")"

  write_version "$VERSION_FILE" "$format" "$new_version"
  write_changelog "$CHANGELOG_FILE" "$new_version" "$COMMITS_FILE"

  echo "$new_version"
}

main "$@"
