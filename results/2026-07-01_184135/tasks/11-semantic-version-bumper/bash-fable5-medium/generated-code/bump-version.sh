#!/usr/bin/env bash
# bump-version.sh — semantic version bumper driven by conventional commits.
#
# Reads the current version from a VERSION file or package.json, inspects a
# commit log (a file of commit subject lines), decides the bump type
# (breaking -> major, feat -> minor, fix -> patch), rewrites the version
# file, prepends a changelog entry, and prints the new version to stdout.
#
# The script only defines functions when sourced, so the bats suite can
# unit-test each function in isolation.

set -euo pipefail

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# die MESSAGE — print an error to stderr and exit non-zero.
die() {
  echo "ERROR: $*" >&2
  return 1
}

# read_version FILE — print the semver stored in FILE.
# Supports plain version files and package.json (detected by .json suffix).
read_version() {
  local file="$1" version
  [[ -f "$file" ]] || { die "version file not found: $file"; return 1; }
  if [[ "$file" == *.json ]]; then
    # Extract the "version" field without requiring jq, so the script has
    # no dependencies beyond coreutils + sed/grep.
    version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n1)"
  else
    version="$(head -n1 "$file" | tr -d '[:space:]')"
  fi
  [[ "$version" =~ $SEMVER_RE ]] \
    || { die "'$version' in $file is not a valid semantic version (expected X.Y.Z)"; return 1; }
  echo "$version"
}

# determine_bump COMMITS_FILE — print major|minor|patch|none.
# Scans conventional-commit subject lines; the highest-priority change wins:
#   breaking (type! or BREAKING CHANGE footer) > feat > fix > everything else.
determine_bump() {
  local file="$1" bump="none" line
  # Regexes live in variables: bash's [[ =~ ]] parser mis-handles inline
  # patterns containing parentheses. "type(scope)!:" marks a breaking
  # change, as does a "BREAKING CHANGE:" footer anywhere in the body.
  local breaking_re='^[a-zA-Z]+(\([^)]*\))?!:'
  local feat_re='^feat(\([^)]*\))?:'
  local fix_re='^fix(\([^)]*\))?:'
  [[ -f "$file" ]] || { die "commit log not found: $file"; return 1; }
  while IFS= read -r line; do
    if [[ "$line" =~ $breaking_re ]] || [[ "$line" == *"BREAKING CHANGE"* ]]; then
      bump="major"
      break # nothing outranks major, stop scanning
    elif [[ "$line" =~ $feat_re ]]; then
      bump="minor"
    elif [[ "$line" =~ $fix_re ]] && [[ "$bump" != "minor" ]]; then
      bump="patch"
    fi
  done < "$file"
  echo "$bump"
}

# bump_version CURRENT TYPE — print the incremented version.
bump_version() {
  local version="$1" type="$2" major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *)     die "unknown bump type: '$type' (expected major, minor, or patch)"; return 1 ;;
  esac
}

# write_version FILE NEW_VERSION — persist the new version.
# For .json files only the "version" field is rewritten; anything else is a
# plain version file that gets replaced wholesale.
write_version() {
  local file="$1" version="$2"
  [[ -f "$file" ]] || { die "version file not found: $file"; return 1; }
  if [[ "$file" == *.json ]]; then
    sed -i 's/\("version"[[:space:]]*:[[:space:]]*"\)[^"]*"/\1'"$version"'"/' "$file"
  else
    echo "$version" > "$file"
  fi
}

# changelog_section CHANGELOG_FILE HEADING REGEX COMMITS_FILE — helper that
# appends a "### HEADING" section listing commits whose subject matches REGEX.
changelog_section() {
  local out="$1" heading="$2" regex="$3" commits="$4" line matched=0
  while IFS= read -r line; do
    if [[ "$line" =~ $regex ]]; then
      [[ $matched -eq 0 ]] && { printf '### %s\n\n' "$heading" >> "$out"; matched=1; }
      # Strip the "type(scope): " prefix so the changelog reads naturally.
      printf -- '- %s\n' "${line#*: }" >> "$out"
    fi
  done < "$commits"
  [[ $matched -eq 1 ]] && printf '\n' >> "$out"
  return 0
}

# generate_changelog NEW_VERSION COMMITS_FILE CHANGELOG_FILE — prepend an
# entry for NEW_VERSION, grouping commits into Breaking/Features/Fixes.
generate_changelog() {
  local version="$1" commits="$2" changelog="$3" entry
  local breaking_re='^[a-zA-Z]+(\([^)]*\))?!:'
  local feat_re='^feat(\([^)]*\))?:'
  local fix_re='^fix(\([^)]*\))?:'
  [[ -f "$commits" ]] || { die "commit log not found: $commits"; return 1; }
  entry="$(mktemp)"
  printf '## %s (%s)\n\n' "$version" "$(date +%Y-%m-%d)" > "$entry"
  changelog_section "$entry" "Breaking Changes" "$breaking_re" "$commits"
  changelog_section "$entry" "Features" "$feat_re" "$commits"
  changelog_section "$entry" "Fixes" "$fix_re" "$commits"
  # Prepend: new entry first, then whatever the changelog already contained.
  if [[ -f "$changelog" ]]; then
    cat "$changelog" >> "$entry"
  fi
  mv "$entry" "$changelog"
}

# usage — print CLI help to stderr.
usage() {
  cat >&2 <<'EOF'
Usage: bump-version.sh [--version-file FILE] [--commits-file FILE] [--changelog FILE]

Reads FILE (plain version file or package.json), determines the next semantic
version from conventional commits in the commit log, updates the version file
and changelog, and prints the new version to stdout.

  --version-file FILE  version source/target (default: VERSION)
  --commits-file FILE  commit subjects, one per line (default: commits.txt)
  --changelog FILE     changelog to prepend to (default: CHANGELOG.md)
EOF
}

# main "$@" — CLI entry point.
main() {
  local version_file="VERSION" commits_file="commits.txt" changelog="CHANGELOG.md"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file) version_file="${2:?--version-file needs a value}"; shift 2 ;;
      --commits-file) commits_file="${2:?--commits-file needs a value}"; shift 2 ;;
      --changelog)    changelog="${2:?--changelog needs a value}"; shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      *)              echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  local current bump next
  current="$(read_version "$version_file")"
  bump="$(determine_bump "$commits_file")"

  if [[ "$bump" == "none" ]]; then
    # Nothing release-worthy: leave files untouched, report the fact.
    echo "no version bump needed (no feat/fix/breaking commits found)" >&2
    echo "$current"
    exit 0
  fi

  next="$(bump_version "$current" "$bump")"
  write_version "$version_file" "$next"
  generate_changelog "$next" "$commits_file" "$changelog"
  echo "bumped $current -> $next ($bump)" >&2
  echo "$next"
}

# Run main only when executed, not when sourced by the test suite.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
