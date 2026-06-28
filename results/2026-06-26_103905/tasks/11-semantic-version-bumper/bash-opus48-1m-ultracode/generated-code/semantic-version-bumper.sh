#!/usr/bin/env bash
#
# semantic-version-bumper.sh
#
# Reads a semantic version from a version file (plain VERSION-style file or a
# package.json), inspects conventional-commit messages to decide the next
# version (feat -> minor, fix -> patch, breaking change -> major), updates the
# version file, prepends a changelog entry, and prints the new version.
#
# The script is "source-safe": sourcing it (as the bats unit tests do) only
# defines the svb_* functions; main() runs only when the file is executed.

set -euo pipefail

# svb_read_version FILE
#   Print the current version string found in FILE on stdout.
#   Supports plain version files (the whole file is "1.2.3") and package.json
#   ("version": "1.2.3"). Exits non-zero with a message on stderr if the file
#   is missing or no version can be found.
svb_read_version() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: version file not found: $file" >&2
    return 1
  fi

  local raw version
  raw="$(cat "$file")"

  # Treat the file as JSON when it is named package.json or its first
  # non-whitespace character is '{'. Otherwise treat it as a plain version file.
  if [[ "$file" == *package.json || "$raw" == *'{'* ]]; then
    version="$(svb_json_version "$raw")"
    if [[ -z "$version" ]]; then
      echo "error: no version field found in JSON file: $file" >&2
      return 1
    fi
  else
    # Plain file: the version is the file's content, stripped of all whitespace.
    version="$(printf '%s' "$raw" | tr -d '[:space:]')"
  fi

  # Normalise an optional leading 'v' (e.g. v1.2.3 -> 1.2.3).
  version="${version#v}"
  if [[ -z "$version" ]]; then
    echo "error: empty version in file: $file" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

# svb_json_version JSON_TEXT
#   Extract the value of the top-level "version" key from JSON text. Uses jq
#   when available (robust), otherwise falls back to a grep/sed parse that
#   covers the common, well-formed package.json layout. Prints nothing if no
#   version key is present.
svb_json_version() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    # `// empty` makes jq print nothing (not "null") when the key is absent.
    printf '%s' "$json" | jq -r '.version // empty' 2>/dev/null && return 0
  fi
  # Fallback: first "version": "x.y.z" occurrence.
  printf '%s' "$json" \
    | grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -n1 \
    | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

# svb_validate_semver VERSION
#   Return 0 if VERSION is a valid semantic version (MAJOR.MINOR.PATCH with an
#   optional -prerelease and/or +build suffix), non-zero otherwise.
svb_validate_semver() {
  local v="$1"
  # Numeric core followed by optional prerelease (-...) and build (+...) parts.
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]
}

# svb_bump_version VERSION BUMP_TYPE
#   Print the next version after applying BUMP_TYPE (major|minor|patch) to the
#   MAJOR.MINOR.PATCH core of VERSION. Any prerelease/build suffix is dropped,
#   matching the convention that a release bump produces a clean version.
svb_bump_version() {
  local version="$1" bump="$2"
  if ! svb_validate_semver "$version"; then
    echo "error: invalid current version: $version" >&2
    return 1
  fi
  # Keep only the numeric core (strip any -prerelease/+build).
  local core="${version%%[-+]*}"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$core"

  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *)
      echo "error: unknown bump type: $bump" >&2
      return 1
      ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# svb_determine_bump COMMITS_FILE
#   Read conventional-commit headers (one per line) and print the required
#   bump level using SemVer precedence: any breaking change -> major, else any
#   feat -> minor, else any fix -> patch, else none.
#
#   A breaking change is signalled either by a '!' before the ':' in the
#   header (e.g. "feat!:" or "feat(api)!:") or by a "BREAKING CHANGE" /
#   "BREAKING-CHANGE" token on any line (the conventional-commits footer).
svb_determine_bump() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: commits file not found: $file" >&2
    return 1
  fi

  # Track whether we have seen each signal; report the highest at the end.
  local saw_breaking=0 saw_feat=0 saw_fix=0
  local line type
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Footer-style breaking-change marker anywhere on the line.
    if [[ "$line" =~ BREAKING[\ -]CHANGE ]]; then
      saw_breaking=1
    fi
    # Match a conventional-commit header: type, optional (scope), optional '!'.
    # Captures: 1=type, 2='!' if present.
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z]+)(\([^\)]*\))?(!)?: ]]; then
      type="${BASH_REMATCH[1]}"
      [[ -n "${BASH_REMATCH[3]}" ]] && saw_breaking=1
      case "$type" in
        feat) saw_feat=1 ;;
        fix)  saw_fix=1 ;;
      esac
    fi
  done < "$file"

  if [[ "$saw_breaking" -eq 1 ]]; then
    echo "major"
  elif [[ "$saw_feat" -eq 1 ]]; then
    echo "minor"
  elif [[ "$saw_fix" -eq 1 ]]; then
    echo "patch"
  else
    echo "none"
  fi
}

# svb_generate_changelog NEW_VERSION COMMITS_FILE DATE
#   Print a "Keep a Changelog"-style entry for NEW_VERSION, grouping commits
#   into BREAKING CHANGES / Features / Bug Fixes sections. Scoped commits are
#   rendered as "- **scope:** description". Empty sections are omitted.
svb_generate_changelog() {
  local version="$1" file="$2" date="$3"
  if [[ ! -f "$file" ]]; then
    echo "error: commits file not found: $file" >&2
    return 1
  fi

  local -a breaking=() features=() fixes=()
  local line type scope bang desc bullet
  while IFS= read -r line || [[ -n "$line" ]]; do
    # A "BREAKING CHANGE:" footer contributes its text to the breaking list.
    if [[ "$line" =~ BREAKING[\ -]CHANGE:?[[:space:]]*(.*) ]]; then
      desc="${BASH_REMATCH[1]}"
      [[ -n "$desc" ]] && breaking+=("- $desc")
    fi
    # Parse a conventional-commit header into its parts.
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z]+)(\(([^\)]*)\))?(!)?:[[:space:]]*(.*)$ ]]; then
      type="${BASH_REMATCH[1]}"
      scope="${BASH_REMATCH[3]}"
      bang="${BASH_REMATCH[4]}"
      desc="${BASH_REMATCH[5]}"
      if [[ -n "$scope" ]]; then
        bullet="- **${scope}:** ${desc}"
      else
        bullet="- ${desc}"
      fi
      # A '!' in the header marks the change itself as breaking.
      [[ -n "$bang" ]] && breaking+=("$bullet")
      case "$type" in
        feat) features+=("$bullet") ;;
        fix)  fixes+=("$bullet") ;;
      esac
    fi
  done < "$file"

  # Emit the entry, including only non-empty sections.
  printf '## [%s] - %s\n' "$version" "$date"
  if [[ ${#breaking[@]} -gt 0 ]]; then
    printf '\n### BREAKING CHANGES\n'
    printf '%s\n' "${breaking[@]}"
  fi
  if [[ ${#features[@]} -gt 0 ]]; then
    printf '\n### Features\n'
    printf '%s\n' "${features[@]}"
  fi
  if [[ ${#fixes[@]} -gt 0 ]]; then
    printf '\n### Bug Fixes\n'
    printf '%s\n' "${fixes[@]}"
  fi
}

# svb_write_version FILE NEW_VERSION
#   Update FILE in place with NEW_VERSION. For package.json only the top-level
#   "version" value is rewritten (all other content is preserved); for a plain
#   file the whole content is replaced.
svb_write_version() {
  local file="$1" new="$2"
  if [[ ! -f "$file" ]]; then
    echo "error: version file not found: $file" >&2
    return 1
  fi
  if [[ "$file" == *package.json ]] || grep -q '{' "$file"; then
    # Replace only the first "version": "..." occurrence, preserving the
    # surrounding JSON exactly (including the key's original spacing).
    sed -i -E "0,/(\"version\"[[:space:]]*:[[:space:]]*\")[^\"]+(\")/ s//\\1$new\\2/" "$file"
  else
    printf '%s\n' "$new" > "$file"
  fi
}

# svb_prepend_changelog FILE ENTRY
#   Insert ENTRY at the top of FILE's change list (newest first), creating the
#   file with a standard header if it does not yet exist.
svb_prepend_changelog() {
  local file="$1" entry="$2"
  local tmp
  tmp="$(mktemp)"
  {
    # Standard Keep-a-Changelog header.
    printf '# Changelog\n\n'
    printf 'All notable changes to this project are documented in this file.\n'
    printf 'This project adheres to [Semantic Versioning](https://semver.org/).\n\n'
    # The new entry on top.
    printf '%s\n\n' "$entry"
    # Followed by all previously existing version entries (from the first
    # "## " heading onward), if any.
    if [[ -f "$file" ]]; then
      awk '/^## /{f=1} f{print}' "$file"
    fi
  } > "$tmp"
  mv "$tmp" "$file"
}

# svb_git_commits
#   Print conventional-commit subject lines from git history, limited to
#   commits since the most recent tag when one exists (otherwise the whole
#   history). Used when no explicit --commits-file is supplied.
svb_git_commits() {
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: not a git repository and no --commits-file given" >&2
    return 1
  fi
  local last_tag range=""
  if last_tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    range="${last_tag}..HEAD"
  fi
  # %s is the subject line; this matches the one-header-per-line contract.
  if [[ -n "$range" ]]; then
    git log "$range" --pretty=format:'%s'
  else
    git log --pretty=format:'%s'
  fi
}

# svb_default_version_file
#   Pick the version file to use when --version-file is not provided:
#   prefer ./VERSION, fall back to ./package.json.
svb_default_version_file() {
  if [[ -f VERSION ]]; then
    echo "VERSION"
  elif [[ -f package.json ]]; then
    echo "package.json"
  else
    echo "VERSION"
  fi
}

# svb_usage
#   Print CLI usage information.
svb_usage() {
  cat <<'USAGE'
Usage: semantic-version-bumper.sh [OPTIONS]

Determine the next semantic version from conventional commits, update the
version file, write a changelog entry, and print the new version.

Options:
  --version-file FILE     Version file to read/update (default: VERSION, or
                          package.json if VERSION is absent).
  --commits-file FILE     File with one conventional-commit header per line.
                          When omitted, commit subjects are read from git log.
  --changelog-file FILE   Changelog file to update (default: CHANGELOG.md).
  --date YYYY-MM-DD       Date for the changelog entry (default: today).
  --dry-run               Compute the new version without modifying any files.
  -h, --help              Show this help and exit.

Bump rules (Conventional Commits -> SemVer):
  breaking change ('type!:' or 'BREAKING CHANGE')  -> major
  feat                                             -> minor
  fix                                              -> patch
  anything else                                    -> no bump

Output:
  Human-readable summary plus a machine-readable 'NEW_VERSION=<version>' line.
  When run inside GitHub Actions, 'new_version' and 'bump_type' are also written
  to $GITHUB_OUTPUT.
USAGE
}

# svb_main "$@"
#   Parse options and run the full bump workflow.
svb_main() {
  local version_file="" commits_file="" changelog_file="CHANGELOG.md"
  local date="" dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file)   version_file="${2:?--version-file needs a value}"; shift 2 ;;
      --commits-file)   commits_file="${2:?--commits-file needs a value}"; shift 2 ;;
      --changelog-file) changelog_file="${2:?--changelog-file needs a value}"; shift 2 ;;
      --date)           date="${2:?--date needs a value}"; shift 2 ;;
      --dry-run)        dry_run=1; shift ;;
      -h|--help)        svb_usage; return 0 ;;
      *)
        echo "error: unknown option: $1" >&2
        svb_usage >&2
        return 2
        ;;
    esac
  done

  [[ -z "$version_file" ]] && version_file="$(svb_default_version_file)"
  [[ -z "$date" ]] && date="$(date +%F)"

  # 1. Current version.
  local current
  current="$(svb_read_version "$version_file")" || return 1

  # 2. Resolve the commit source. With --commits-file we use it directly; with
  #    git we materialise the subjects into a temp file so the same code path
  #    serves both.
  local commits cleanup_commits=0
  if [[ -n "$commits_file" ]]; then
    if [[ ! -f "$commits_file" ]]; then
      echo "error: commits file not found: $commits_file" >&2
      return 1
    fi
    commits="$commits_file"
  else
    commits="$(mktemp)"
    cleanup_commits=1
    svb_git_commits > "$commits" || { rm -f "$commits"; return 1; }
  fi

  # 3. Decide the bump level.
  local bump
  bump="$(svb_determine_bump "$commits")" || { [[ $cleanup_commits -eq 1 ]] && rm -f "$commits"; return 1; }

  echo "Current version: $current"
  echo "Bump type: $bump"

  if [[ "$bump" == "none" ]]; then
    echo "No version bump required (no feat/fix/breaking commits found)."
    echo "New version: $current"
    echo "NEW_VERSION=$current"
    svb_emit_github_output "$current" "$bump"
    [[ $cleanup_commits -eq 1 ]] && rm -f "$commits"
    return 0
  fi

  # 4. Compute the new version.
  local new
  new="$(svb_bump_version "$current" "$bump")" || { [[ $cleanup_commits -eq 1 ]] && rm -f "$commits"; return 1; }

  if [[ "$dry_run" -eq 1 ]]; then
    echo "(dry-run) Would update $version_file and $changelog_file"
  else
    # 5. Persist: version file first, then changelog.
    svb_write_version "$version_file" "$new"
    local entry
    entry="$(svb_generate_changelog "$new" "$commits" "$date")"
    svb_prepend_changelog "$changelog_file" "$entry"
    echo "Updated $version_file and $changelog_file"
  fi

  echo "New version: $new"
  echo "NEW_VERSION=$new"
  svb_emit_github_output "$new" "$bump"

  [[ $cleanup_commits -eq 1 ]] && rm -f "$commits"
  return 0
}

# svb_emit_github_output NEW_VERSION BUMP_TYPE
#   When running inside GitHub Actions, expose results as step outputs and add
#   a short summary. No-op outside CI.
svb_emit_github_output() {
  local new="$1" bump="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "new_version=$new"
      echo "bump_type=$bump"
    } >> "$GITHUB_OUTPUT"
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Semantic version bumper"
      echo ""
      echo "- Bump type: \`$bump\`"
      echo "- New version: \`$new\`"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# Run main() only when the script is executed directly. When sourced (e.g. by
# the bats unit tests) this guard is false, so only the functions are defined.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  svb_main "$@"
fi
