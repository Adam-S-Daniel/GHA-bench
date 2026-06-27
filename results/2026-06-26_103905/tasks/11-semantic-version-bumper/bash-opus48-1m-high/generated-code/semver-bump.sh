#!/usr/bin/env bash
#
# semver-bump.sh — Semantic Version Bumper
#
# Reads a semantic version from a version file (a plain VERSION file or a
# package.json), inspects conventional-commit messages to decide whether the
# next release is a major/minor/patch bump, writes the new version back to the
# file, appends a changelog entry, and prints the new version to stdout.
#
# Conventional commit -> bump mapping:
#   * a breaking change ("feat!:", "fix!:", any "type!:", or a "BREAKING CHANGE:"
#     footer)            -> major
#   * "feat:"            -> minor
#   * "fix:"             -> patch
#   * anything else      -> ignored
# The highest-precedence change among all commits wins (major > minor > patch).
#
# The script is intentionally split into small, independently testable
# functions. Sourcing the file does not run main(), so unit tests can call the
# functions directly.

set -euo pipefail

# parse_version FILE
#
# Extract the semantic version string from FILE. Supports a plain text file
# whose contents are just the version (e.g. "1.2.3") and a package.json with a
# top-level "version" field. Prints the version on success.
parse_version() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: version file not found: $file" >&2
    return 1
  fi

  if [[ "$(basename "$file")" == "package.json" ]]; then
    # Pull the first top-level "version": "x.y.z" out of the JSON with sed so we
    # do not depend on jq being installed in every environment.
    local version
    version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n1)"
    if [[ -z "$version" ]]; then
      echo "error: no \"version\" field found in $file" >&2
      return 1
    fi
    printf '%s\n' "$version"
  else
    # Plain version file: take the first non-empty, trimmed line.
    local line
    line="$(grep -m1 -v '^[[:space:]]*$' "$file" || true)"
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    if [[ -z "$line" ]]; then
      echo "error: version file is empty: $file" >&2
      return 1
    fi
    printf '%s\n' "$line"
  fi
}

# validate_version VERSION
#
# Returns 0 if VERSION is a strict MAJOR.MINOR.PATCH semantic version (digits
# only). Prints an error and returns 1 otherwise.
validate_version() {
  local version="$1"
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi
  echo "error: invalid semantic version: '$version' (expected MAJOR.MINOR.PATCH)" >&2
  return 1
}

# determine_bump COMMITS_FILE
#
# Scan a file of commit messages (one logical commit may span several lines)
# and print the required bump level: "major", "minor", "patch", or "none".
# The highest precedence wins. A breaking change is signalled either by a "!"
# before the colon in the header (e.g. "feat!:") or by a "BREAKING CHANGE:" /
# "BREAKING-CHANGE:" footer anywhere in the messages.
determine_bump() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: commits file not found: $file" >&2
    return 1
  fi

  local bump="none"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Breaking change footer -> major, short-circuit immediately.
    if [[ "$line" =~ ^BREAKING[\ -]CHANGE: ]]; then
      echo "major"
      return 0
    fi
    # Conventional commit header: type, optional scope, optional "!", colon.
    if [[ "$line" =~ ^([a-zA-Z]+)(\([^\)]*\))?(!)?: ]]; then
      local type="${BASH_REMATCH[1]}"
      local breaking="${BASH_REMATCH[3]}"
      if [[ -n "$breaking" ]]; then
        echo "major"
        return 0
      fi
      case "$type" in
        feat) [[ "$bump" == "none" || "$bump" == "patch" ]] && bump="minor" ;;
        fix)  [[ "$bump" == "none" ]] && bump="patch" ;;
      esac
    fi
  done < "$file"

  echo "$bump"
}

# bump_version VERSION BUMP
#
# Print VERSION incremented according to BUMP (major|minor|patch|none).
# Resets lower-order components per semver rules. "none" returns VERSION as-is.
bump_version() {
  local version="$1" bump="$2"
  validate_version "$version" || return 1

  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"

  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    none)  : ;;  # no change
    *) echo "error: unknown bump type: $bump" >&2; return 1 ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# update_version_file FILE NEW_VERSION
#
# Write NEW_VERSION back into FILE. For package.json, only the top-level
# "version" field is rewritten (other strings are left intact). For a plain
# version file, the whole file becomes the new version.
update_version_file() {
  local file="$1" new_version="$2"
  if [[ ! -f "$file" ]]; then
    echo "error: version file not found: $file" >&2
    return 1
  fi
  validate_version "$new_version" || return 1

  if [[ "$(basename "$file")" == "package.json" ]]; then
    # Replace only the first "version": "..." occurrence. A temp file keeps the
    # operation atomic-ish and avoids sed -i portability concerns.
    local tmp="${file}.tmp.$$"
    sed '0,/"version"[[:space:]]*:[[:space:]]*"[^"]*"/s//"version": "'"$new_version"'"/' \
      "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s\n' "$new_version" > "$file"
  fi
}

# generate_changelog COMMITS_FILE NEW_VERSION CHANGELOG_FILE [DATE]
#
# Build a "Keep a Changelog"-style entry for NEW_VERSION from the conventional
# commits in COMMITS_FILE and prepend it to CHANGELOG_FILE (creating the file
# with a top-level title if it does not yet exist). DATE defaults to today.
generate_changelog() {
  local commits_file="$1" new_version="$2" changelog_file="$3"
  local date="${4:-$(date +%Y-%m-%d)}"

  if [[ ! -f "$commits_file" ]]; then
    echo "error: commits file not found: $commits_file" >&2
    return 1
  fi

  # Collect bullet lines per category, stripping the "type(scope)!: " prefix so
  # the changelog reads as a human-friendly description.
  local features="" fixes="" breaking="" line desc
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^BREAKING[\ -]CHANGE:[[:space:]]*(.*)$ ]]; then
      breaking+="- ${BASH_REMATCH[1]}"$'\n'
      continue
    fi
    if [[ "$line" =~ ^([a-zA-Z]+)(\([^\)]*\))?(!)?:[[:space:]]*(.*)$ ]]; then
      local type="${BASH_REMATCH[1]}"
      local bang="${BASH_REMATCH[3]}"
      desc="${BASH_REMATCH[4]}"
      if [[ -n "$bang" ]]; then
        breaking+="- ${desc}"$'\n'
      fi
      case "$type" in
        feat) features+="- ${desc}"$'\n' ;;
        fix)  fixes+="- ${desc}"$'\n' ;;
      esac
    fi
  done < "$commits_file"

  # Assemble the new entry in a buffer.
  local entry="## [${new_version}] - ${date}"$'\n'
  if [[ -n "$breaking" ]]; then
    entry+=$'\n'"### Breaking Changes"$'\n'"${breaking}"
  fi
  if [[ -n "$features" ]]; then
    entry+=$'\n'"### Features"$'\n'"${features}"
  fi
  if [[ -n "$fixes" ]]; then
    entry+=$'\n'"### Fixes"$'\n'"${fixes}"
  fi

  # Prepend the entry, preserving any existing changelog body.
  local tmp="${changelog_file}.tmp.$$"
  if [[ -f "$changelog_file" ]] && grep -q '^# ' "$changelog_file"; then
    # Keep the existing "# Changelog" title line, then the new entry, then the rest.
    {
      head -n1 "$changelog_file"
      printf '\n%s\n' "$entry"
      tail -n +2 "$changelog_file"
    } > "$tmp"
  else
    {
      printf '# Changelog\n\n'
      printf '%s\n' "$entry"
      [[ -f "$changelog_file" ]] && cat "$changelog_file"
    } > "$tmp"
  fi
  mv "$tmp" "$changelog_file"
}

# usage
#
# Print command-line usage to stdout.
usage() {
  cat <<'USAGE'
Usage: semver-bump.sh --version-file FILE --commits FILE [options]

Determine the next semantic version from conventional-commit messages, update
the version file, generate a changelog entry, and print the new version.

Required:
  --version-file FILE   Path to a VERSION file or package.json to read/update.
  --commits FILE        Path to a file of commit messages (one per line; commit
                        bodies may span multiple lines).

Optional:
  --changelog FILE      Path to the changelog to prepend to (default: CHANGELOG.md).
  --date YYYY-MM-DD     Date for the changelog entry (default: today).
  --dry-run             Compute and print the new version without writing files.
  -h, --help            Show this help and exit.

Exit status:
  0  Success (including "nothing to release", which echoes the current version).
  1  Usage error or I/O error.
USAGE
}

# main ARGS...
#
# Parse CLI arguments and run the full bump pipeline.
main() {
  local version_file="" commits_file="" changelog_file="CHANGELOG.md"
  local date="" dry_run="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file) version_file="${2:-}"; shift 2 ;;
      --commits)      commits_file="${2:-}"; shift 2 ;;
      --changelog)    changelog_file="${2:-}"; shift 2 ;;
      --date)         date="${2:-}"; shift 2 ;;
      --dry-run)      dry_run="true"; shift ;;
      -h|--help)      usage; return 0 ;;
      *) echo "error: unknown argument: $1" >&2; usage >&2; return 1 ;;
    esac
  done

  if [[ -z "$version_file" || -z "$commits_file" ]]; then
    echo "error: --version-file and --commits are required" >&2
    usage >&2
    return 1
  fi

  # Read and validate the current version.
  local current_version
  current_version="$(parse_version "$version_file")" || return 1
  validate_version "$current_version" || return 1

  # Decide the bump from the commit messages.
  local bump
  bump="$(determine_bump "$commits_file")" || return 1

  # Nothing releasable: echo the current version unchanged and succeed.
  if [[ "$bump" == "none" ]]; then
    echo "no releasable commits found; version unchanged" >&2
    printf '%s\n' "$current_version"
    return 0
  fi

  # Compute the next version.
  local new_version
  new_version="$(bump_version "$current_version" "$bump")" || return 1

  if [[ "$dry_run" == "true" ]]; then
    echo "dry-run: would bump $current_version -> $new_version ($bump)" >&2
    printf '%s\n' "$new_version"
    return 0
  fi

  # Apply the changes.
  update_version_file "$version_file" "$new_version" || return 1
  if [[ -n "$date" ]]; then
    generate_changelog "$commits_file" "$new_version" "$changelog_file" "$date" || return 1
  else
    generate_changelog "$commits_file" "$new_version" "$changelog_file" || return 1
  fi

  echo "bumped $current_version -> $new_version ($bump)" >&2
  printf '%s\n' "$new_version"
}

# Only run main() when executed directly, not when sourced by the tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
