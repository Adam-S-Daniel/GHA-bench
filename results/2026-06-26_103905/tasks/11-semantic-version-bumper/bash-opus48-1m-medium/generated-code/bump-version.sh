#!/usr/bin/env bash
#
# bump-version.sh — Semantic version bumper driven by Conventional Commits.
#
# Given a current version (in a plain version file or a package.json) and a
# list of commit messages, this script:
#   1. Determines the next version using Conventional Commit rules:
#        - any breaking change ("type!:" or a "BREAKING CHANGE:" footer) -> major
#        - otherwise any "feat" commit                                   -> minor
#        - otherwise any "fix" commit                                    -> patch
#        - otherwise: no bump (treated as an error so CI can react)
#   2. Updates the version file / package.json in place.
#   3. Appends a changelog entry (grouped by type) to the changelog file.
#   4. Prints the new version to stdout (last line) for easy capture.
#
# The design favours testability: there are no network calls, no git
# invocations and no global state. Commit messages are read from a file so
# they can be supplied as fixtures. Everything is pure text processing.
#
# Exit codes:
#   0  success (a bump was applied)
#   1  usage error / bad input
#   2  no conventional commits found (nothing to bump)

set -euo pipefail

# --- helpers ---------------------------------------------------------------

# Print an error to stderr with a consistent prefix.
err() {
  echo "error: $*" >&2
}

usage() {
  cat >&2 <<'EOF'
Usage: bump-version.sh (--version-file FILE | --package-json FILE) --commits FILE
                       [--changelog FILE]

Options:
  --version-file FILE   Plain-text file containing a semantic version string
                        (optionally prefixed with "v"). Updated in place.
  --package-json FILE   package.json whose "version" field is read and updated.
  --commits FILE        File containing commit messages (one subject per line;
                        bodies/footers may follow on their own lines). Required.
  --changelog FILE      Changelog file to append an entry to (default: none).
  -h, --help            Show this help.

Exactly one of --version-file / --package-json must be given.
EOF
}

# Extract a "version" field value from a package.json file.
# Uses a tolerant regex rather than a JSON parser to keep dependencies at zero.
read_package_json_version() {
  local file="$1" line
  line="$(grep -E '"version"[[:space:]]*:' "$file" | head -n1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  # Strip everything except the value inside the quotes after the colon.
  printf '%s\n' "$line" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}

# Validate that a string is a plain X.Y.Z semantic version (no pre-release/meta
# for the purposes of bumping). Returns 0 if valid.
is_valid_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# --- argument parsing ------------------------------------------------------

version_file=""
package_json=""
commits_file=""
changelog_file=""

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version-file)
      version_file="${2:-}"; shift 2 ;;
    --package-json)
      package_json="${2:-}"; shift 2 ;;
    --commits)
      commits_file="${2:-}"; shift 2 ;;
    --changelog)
      changelog_file="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "unknown argument: $1"; usage; exit 1 ;;
  esac
done

# Validate the mutually-exclusive source-of-version options.
if [ -n "$version_file" ] && [ -n "$package_json" ]; then
  err "give only one of --version-file or --package-json"
  exit 1
fi
if [ -z "$version_file" ] && [ -z "$package_json" ]; then
  err "one of --version-file or --package-json is required"
  usage
  exit 1
fi
if [ -z "$commits_file" ]; then
  err "--commits is required"
  usage
  exit 1
fi
if [ ! -f "$commits_file" ]; then
  err "commits file not found: $commits_file"
  exit 1
fi

# --- read current version --------------------------------------------------

prefix=""        # preserved "v" prefix, if any
current=""       # current X.Y.Z

if [ -n "$package_json" ]; then
  if [ ! -f "$package_json" ]; then
    err "package.json not found: $package_json"
    exit 1
  fi
  if ! current="$(read_package_json_version "$package_json")"; then
    err "could not find a \"version\" field in $package_json"
    exit 1
  fi
else
  if [ ! -f "$version_file" ]; then
    err "version file not found: $version_file"
    exit 1
  fi
  # Read the first non-empty line as the version string.
  current="$(grep -m1 -v '^[[:space:]]*$' "$version_file" | tr -d '[:space:]' || true)"
fi

# Detect and strip an optional leading "v".
if [[ "$current" == v* ]]; then
  prefix="v"
  current="${current#v}"
fi

if ! is_valid_semver "$current"; then
  err "invalid/malformed version string: '${prefix}${current}'"
  exit 1
fi

# --- determine bump type from commits --------------------------------------

# We scan every commit message line. Conventional Commit subjects look like:
#   <type>[optional scope][!]: <description>
# A breaking change is signalled either by a "!" before the colon or by a
# "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer anywhere in the message body.

bump=""   # one of: major, minor, patch (empty => none)

# Collect commit subjects per type for the changelog while we are scanning.
feat_lines=()
fix_lines=()
breaking_lines=()

# rank: major=3, minor=2, patch=1, none=0
rank=0
set_bump() {
  local want="$1" want_rank="$2"
  if [ "$want_rank" -gt "$rank" ]; then
    rank="$want_rank"
    bump="$want"
  fi
}

while IFS= read -r line || [ -n "$line" ]; do
  # A breaking-change footer triggers a major bump regardless of subject type.
  if [[ "$line" =~ ^BREAKING[\ -]CHANGE: ]]; then
    set_bump major 3
    breaking_lines+=("${line#*: }")
    continue
  fi

  # Match a conventional commit subject. Capture type, optional "!", and desc.
  if [[ "$line" =~ ^([a-zA-Z]+)(\([^\)]*\))?(!)?:[[:space:]]*(.*)$ ]]; then
    type="${BASH_REMATCH[1],,}"   # lower-case the type
    bang="${BASH_REMATCH[3]}"
    desc="${BASH_REMATCH[4]}"

    if [ -n "$bang" ]; then
      set_bump major 3
      breaking_lines+=("$desc")
    fi

    case "$type" in
      feat)
        set_bump minor 2
        feat_lines+=("$desc") ;;
      fix)
        set_bump patch 1
        fix_lines+=("$desc") ;;
      *)
        : ;;  # other types (chore, docs, refactor, ...) don't drive a bump
    esac
  fi
done < "$commits_file"

if [ -z "$bump" ]; then
  err "no conventional commits found; no version bump"
  exit 2
fi

# --- compute the new version -----------------------------------------------

IFS='.' read -r major minor patch <<< "$current"

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

new_version="${major}.${minor}.${patch}"

# --- write the new version back --------------------------------------------

if [ -n "$package_json" ]; then
  # Replace the first "version" value, preserving formatting/indentation.
  tmp="$(mktemp)"
  sed -E "0,/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s//\"version\": \"${new_version}\"/" \
    "$package_json" > "$tmp"
  mv "$tmp" "$package_json"
else
  printf '%s\n' "${prefix}${new_version}" > "$version_file"
fi

# --- generate the changelog entry ------------------------------------------

if [ -n "$changelog_file" ]; then
  {
    echo "## ${new_version}"
    echo ""
    if [ "${#breaking_lines[@]}" -gt 0 ]; then
      echo "### BREAKING CHANGES"
      echo ""
      for l in "${breaking_lines[@]}"; do echo "- ${l}"; done
      echo ""
    fi
    if [ "${#feat_lines[@]}" -gt 0 ]; then
      echo "### Features"
      echo ""
      for l in "${feat_lines[@]}"; do echo "- ${l}"; done
      echo ""
    fi
    if [ "${#fix_lines[@]}" -gt 0 ]; then
      echo "### Bug Fixes"
      echo ""
      for l in "${fix_lines[@]}"; do echo "- ${l}"; done
      echo ""
    fi
  } > "${changelog_file}.new"

  # Prepend the new entry above any existing changelog content.
  if [ -f "$changelog_file" ]; then
    cat "$changelog_file" >> "${changelog_file}.new"
  fi
  mv "${changelog_file}.new" "$changelog_file"
fi

# --- emit results ----------------------------------------------------------

# Human-friendly summary on stderr; machine-friendly version on stdout.
echo "Bumped ${prefix}${current} -> ${prefix}${new_version} (${bump})" >&2
echo "${prefix}${new_version}"
