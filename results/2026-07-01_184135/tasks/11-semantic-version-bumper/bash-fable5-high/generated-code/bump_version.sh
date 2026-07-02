#!/usr/bin/env bash
# =============================================================================
# bump_version.sh — semantic version bumper driven by conventional commits.
#
# Reads the current version from a plain VERSION file or a package.json,
# scans a commit log (mock fixture file or `git log`) for conventional
# commit prefixes, bumps the version accordingly (breaking -> major,
# feat -> minor, fix -> patch), rewrites the version file, prepends a
# changelog entry, and prints the new version on stdout.
#
# Built with red/green TDD (see tests/bump_version.bats); functions are
# sourceable for unit testing: `BUMP_VERSION_LIB=1 source bump_version.sh`.
# =============================================================================
set -euo pipefail

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# die MESSAGE [EXIT_CODE] — print a meaningful error and abort.
die() {
  echo "bump_version: error: $1" >&2
  exit "${2:-1}"
}

# read_current_version FILE
# Prints the semantic version stored in FILE. Supports plain version files
# (single X.Y.Z line) and package.json ("version" field).
read_current_version() {
  local file="$1" version
  [[ -f "$file" ]] || die "version file not found: $file" 2
  if [[ "$(basename "$file")" == "package.json" ]]; then
    # Extract the first "version": "X.Y.Z" occurrence without requiring jq,
    # so the script has zero dependencies beyond coreutils/sed/grep.
    version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -n1)"
    [[ -n "$version" ]] || die "no \"version\" field found in $file" 2
  else
    version="$(head -n1 "$file" | tr -d '[:space:]')"
  fi
  [[ "$version" =~ $SEMVER_RE ]] || die "invalid semantic version in $file: '$version'" 2
  echo "$version"
}

# determine_bump COMMIT_LOG_FILE
# Scans one commit message per line (bodies/footers may follow on their own
# lines, as produced by `git log --format=%s%n%b`) and prints the strongest
# bump implied by conventional commits:
#   breaking (type!: or BREAKING CHANGE footer) -> major
#   feat                                        -> minor
#   fix                                         -> patch
#   anything else (docs, chore, style, ...)     -> none
determine_bump() {
  local file="$1" line bump="none"
  [[ -f "$file" ]] || die "commit log not found: $file" 2
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Breaking change: "type!:" / "type(scope)!:" prefix or a BREAKING
    # CHANGE / BREAKING-CHANGE footer anywhere in the message body.
    if [[ "$line" =~ ^[a-zA-Z]+(\([^\)]*\))?!: ]] || [[ "$line" =~ ^BREAKING([- ])CHANGE ]]; then
      echo "major"
      return 0
    elif [[ "$line" =~ ^feat(\([^\)]*\))?: ]]; then
      bump="minor"
    elif [[ "$line" =~ ^fix(\([^\)]*\))?: ]] && [[ "$bump" == "none" ]]; then
      bump="patch"
    fi
  done < "$file"
  echo "$bump"
}

# apply_bump CURRENT_VERSION BUMP_TYPE
# Prints the incremented version. "none" passes the version through so
# callers can treat every bump type uniformly.
apply_bump() {
  local version="$1" bump="$2" major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    none)  echo "$version" ;;
    *)     die "unknown bump type: '$bump'" 1 ;;
  esac
}

# write_version FILE NEW_VERSION
# Persists NEW_VERSION into FILE, preserving package.json structure by
# rewriting only the first "version" field; plain files are replaced whole.
write_version() {
  local file="$1" new_version="$2" tmp
  [[ -f "$file" ]] || die "version file not found: $file" 2
  if [[ "$(basename "$file")" == "package.json" ]]; then
    # sed edits only the first line carrying a "version" field; a temp file
    # plus mv keeps the update atomic.
    tmp="$(mktemp)"
    sed -E '0,/"version"[[:space:]]*:[[:space:]]*"[^"]*"/s//"version": "'"$new_version"'"/' \
      "$file" > "$tmp" || die "failed to update $file" 2
    mv "$tmp" "$file"
  else
    printf '%s\n' "$new_version" > "$file"
  fi
}

# render_changelog_entry NEW_VERSION DATE COMMIT_LOG_FILE
# Prints a markdown changelog entry with commits grouped into Breaking
# Changes / Features / Fixes. Empty sections are omitted. The description
# after "type:" / "type(scope)!:" becomes the bullet text.
render_changelog_entry() {
  local version="$1" date="$2" file="$3"
  local line desc breaking="" features="" fixes=""
  [[ -f "$file" ]] || die "commit log not found: $file" 2
  while IFS= read -r line || [[ -n "$line" ]]; do
    desc="${line#*: }"
    if [[ "$line" =~ ^[a-zA-Z]+(\([^\)]*\))?!: ]]; then
      breaking+="- $desc"$'\n'
    elif [[ "$line" =~ ^BREAKING([- ])CHANGE ]]; then
      breaking+="- ${line#*: }"$'\n'
    elif [[ "$line" =~ ^feat(\([^\)]*\))?: ]]; then
      features+="- $desc"$'\n'
    elif [[ "$line" =~ ^fix(\([^\)]*\))?: ]]; then
      fixes+="- $desc"$'\n'
    fi
  done < "$file"

  echo "## $version ($date)"
  [[ -n "$breaking" ]] && printf '\n### Breaking Changes\n\n%s' "$breaking"
  [[ -n "$features" ]] && printf '\n### Features\n\n%s' "$features"
  [[ -n "$fixes"    ]] && printf '\n### Fixes\n\n%s' "$fixes"
  return 0
}

# prepend_changelog CHANGELOG_FILE ENTRY
# Inserts ENTRY at the top of the changelog (newest release first),
# creating the file on first use.
prepend_changelog() {
  local file="$1" entry="$2" tmp
  tmp="$(mktemp)"
  {
    printf '%s\n' "$entry"
    if [[ -s "$file" ]]; then
      echo ""
      cat "$file"
    fi
  } > "$tmp"
  mv "$tmp" "$file"
}

usage() {
  cat <<'EOF'
Usage: bump_version.sh --version-file FILE [OPTIONS]

Bump a semantic version based on conventional commit messages.

Options:
  --version-file FILE  Version source: plain file with X.Y.Z, or package.json (required)
  --commits FILE       Commit log, one conventional subject per line
                       (default: `git log --format=%s%n%b` since the last tag)
  --changelog FILE     Changelog to prepend the release notes to (default: CHANGELOG.md)
  --date YYYY-MM-DD    Release date for the changelog heading (default: today)
  -h, --help           Show this help

Output: the new version is printed as the last line of stdout. When run in
GitHub Actions, new_version/old_version/bump_type are appended to $GITHUB_OUTPUT.
EOF
}

# collect_git_commits OUT_FILE
# Fallback commit source when --commits is not given: subjects + bodies since
# the most recent tag (or the whole history when the repo has no tags yet).
collect_git_commits() {
  local out="$1" range="HEAD" last_tag
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository and no --commits file given" 2
  if last_tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    range="$last_tag..HEAD"
  fi
  git log --format='%s%n%b' "$range" > "$out"
}

main() {
  local version_file="" commits_file="" changelog_file="CHANGELOG.md"
  local date="" current_version new_version bump tmp_commits=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file) version_file="${2:-}"; shift 2 ;;
      --commits)      commits_file="${2:-}"; shift 2 ;;
      --changelog)    changelog_file="${2:-}"; shift 2 ;;
      --date)         date="${2:-}"; shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      *)              usage >&2; die "unknown option: $1" 1 ;;
    esac
  done

  [[ -n "$version_file" ]] || { usage >&2; die "--version-file is required" 1; }
  [[ -n "$date" ]] || date="$(date +%Y-%m-%d)"

  # No --commits file? Fall back to the real git history.
  if [[ -z "$commits_file" ]]; then
    tmp_commits="$(mktemp)"
    trap 'rm -f "$tmp_commits"' EXIT
    collect_git_commits "$tmp_commits"
    commits_file="$tmp_commits"
  fi

  current_version="$(read_current_version "$version_file")"
  bump="$(determine_bump "$commits_file")"
  new_version="$(apply_bump "$current_version" "$bump")"

  if [[ "$bump" == "none" ]]; then
    echo "bump_version: no version bump needed (no feat/fix/breaking commits found)" >&2
  else
    write_version "$version_file" "$new_version"
    prepend_changelog "$changelog_file" \
      "$(render_changelog_entry "$new_version" "$date" "$commits_file")"
  fi

  # Machine-readable summary for humans/CI logs, then the bare version last
  # so `tail -n1` (or bats `${lines[-1]}`) always yields it.
  echo "bump_version: $current_version -> $new_version ($bump)" >&2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "old_version=$current_version"
      echo "new_version=$new_version"
      echo "bump_type=$bump"
    } >> "$GITHUB_OUTPUT"
  fi
  echo "$new_version"
}

# When sourced as a library for tests, expose functions only. `return` is
# valid here because BUMP_VERSION_LIB=1 implies the file is being sourced.
if [[ "${BUMP_VERSION_LIB:-0}" == "1" ]]; then
  # shellcheck disable=SC2317
  return 0
fi

main "$@"
