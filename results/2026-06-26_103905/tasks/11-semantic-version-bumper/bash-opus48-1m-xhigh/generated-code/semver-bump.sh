#!/usr/bin/env bash
#
# semver-bump.sh -- Semantic Version Bumper
# ============================================================================
# Reads a current semantic version (from a plain VERSION file OR a package.json),
# inspects a list of Conventional-Commit messages, decides the next version using
# SemVer rules, updates the version file, prepends a CHANGELOG entry, and prints
# the resulting version to STDOUT.
#
# Bump rules (Conventional Commits -> SemVer):
#   * a breaking change  ("feat!:", "fix!:", "<type>!:", or a "BREAKING CHANGE")
#       -> MAJOR  (X+1.0.0)
#   * a feature          ("feat:" / "feat(scope):")
#       -> MINOR  (X.Y+1.0)
#   * a fix              ("fix:"  / "fix(scope):")
#       -> PATCH  (X.Y.Z+1)
#   * anything else (chore/docs/style/refactor/test/...) does NOT trigger a bump.
#   * Precedence is highest-wins:  major > minor > patch > none.
#
# Design decisions
# ----------------
#   * STDOUT contains ONLY the new version string, so the script composes cleanly
#     in pipelines / CI:   NEW=$(semver-bump.sh --commits log.txt)
#     All diagnostics go to STDERR.
#   * Commit messages are read from a *file* (one commit subject per line). This
#     keeps the logic deterministic and unit-testable without a real git history
#     -- the "mock commit logs" used as fixtures are exactly these files.
#   * package.json is parsed/written with `jq` (present on GitHub-hosted runners
#     and in the act container). Plain version files are handled in pure bash.
#   * When $GITHUB_OUTPUT is set the script also emits old_version / new_version /
#     bump as step outputs, the idiomatic way to surface data to later GHA steps.
# ============================================================================

set -euo pipefail

# --- small helpers ----------------------------------------------------------

# log: human-readable diagnostics -> STDERR (keeps STDOUT clean for the version)
log() { printf '%s\n' "$*" >&2; }

# die: print an error and abort with a non-zero status
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: semver-bump.sh --commits <file> [options]

Options:
  --version-file <file>  Version source: a plain text file or package.json
                         (default: VERSION)
  --commits <file>       File of Conventional-Commit subjects, one per line
                         (REQUIRED)
  --changelog <file>     Changelog file to prepend the new entry to
                         (default: CHANGELOG.md)
  --date <YYYY-MM-DD>    Release date used in the changelog entry
                         (default: today, or $SEMVER_RELEASE_DATE)
  --dry-run              Compute the new version but do not modify any files
  -h, --help             Show this help

Output:
  The new version string is printed to STDOUT. When $GITHUB_OUTPUT is set,
  old_version / new_version / bump are also written there as step outputs.
EOF
}

# --- version file detection / read / write ----------------------------------

# is_json_file: true when the target should be treated as JSON (package.json).
# Detect by extension first, then fall back to "first non-space char is '{'".
is_json_file() {
  local file="$1" base content
  base=$(basename -- "$file")
  case "$base" in
    *.json) return 0 ;;
  esac
  content=$(tr -d '[:space:]' < "$file" 2>/dev/null || true)
  [[ "${content:0:1}" == "{" ]]
}

# read_version: extract and validate a MAJOR.MINOR.PATCH version from a file.
read_version() {
  local file="$1" raw
  if is_json_file "$file"; then
    raw=$(jq -r '.version // empty' "$file" 2>/dev/null) \
      || die "failed to parse JSON version file: $file"
    [[ -n "$raw" ]] || die "no \".version\" field found in $file"
  else
    # First non-empty, non-comment line. awk avoids a grep|head SIGPIPE/pipefail
    # interaction and is portable.
    raw=$(awk 'NF && $0 !~ /^[[:space:]]*#/ { print; exit }' "$file")
    [[ -n "$raw" ]] || die "version file is empty: $file"
  fi
  raw=$(printf '%s' "$raw" | tr -d '[:space:]')   # strip any surrounding space
  raw="${raw#v}"                                   # tolerate a leading "v"
  [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "invalid semantic version '$raw' in $file (expected MAJOR.MINOR.PATCH)"
  printf '%s' "$raw"
}

# write_version: persist the new version back to the file, preserving format.
write_version() {
  local file="$1" new="$2" tmp
  if is_json_file "$file"; then
    tmp=$(mktemp)
    jq --arg v "$new" '.version = $v' "$file" > "$tmp" \
      || { rm -f "$tmp"; die "failed to update JSON version file: $file"; }
    mv "$tmp" "$file"
  else
    printf '%s\n' "$new" > "$file"
  fi
}

# --- commit parsing ---------------------------------------------------------

# Conventional-Commit regular expressions. They live in variables because bash's
# `[[ =~ ]]` parses an *inline* pattern containing parentheses as shell grammar;
# referencing a variable (unquoted) on the right-hand side avoids that pitfall.
readonly RE_TYPE_SCOPE='^[a-zA-Z]+\(([^)]*)\)!?:[[:space:]]*(.*)$'  # type(scope): desc
readonly RE_TYPE_ONLY='^[a-zA-Z]+!?:[[:space:]]*(.*)$'             # type: desc
readonly RE_BREAKING='^[a-zA-Z]+(\([^)]*\))?!:'                    # type!: / type(scope)!:
readonly RE_BREAKING_FOOTER='^BREAKING[ _-]CHANGE'                 # BREAKING CHANGE / -
readonly RE_FEAT='^feat(\([^)]*\))?:'
readonly RE_FIX='^fix(\([^)]*\))?:'

# clean_desc: turn a raw commit subject into a tidy changelog bullet.
#   "feat(api): add pagination"  -> "**api:** add pagination"
#   "fix: handle null input"     -> "handle null input"
#   anything unrecognised        -> the line, verbatim
clean_desc() {
  local line="$1"
  if [[ "$line" =~ $RE_TYPE_SCOPE ]]; then
    printf '**%s:** %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$line" =~ $RE_TYPE_ONLY ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$line"
  fi
}

# parse_commits: scan the commit log once, classify every commit, and set the
# globals consumed by the caller:
#   BUMP            -> "major" | "minor" | "patch" | "none"
#   BREAKING/FEATS/FIXES -> arrays of cleaned changelog bullets
parse_commits() {
  local file="$1" line
  BUMP="none"
  BREAKING=(); FEATS=(); FIXES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    # skip blank lines and "#" comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Highest-wins precedence (major > minor > patch). Explicit `if` blocks are
    # used instead of `cond && assign` so a false condition does not make the
    # loop/function return non-zero under `set -e`.
    if [[ "$line" =~ $RE_BREAKING ]] || [[ "$line" =~ $RE_BREAKING_FOOTER ]]; then
      BREAKING+=("$(clean_desc "$line")")
      BUMP="major"
    elif [[ "$line" =~ $RE_FEAT ]]; then
      FEATS+=("$(clean_desc "$line")")
      if [[ "$BUMP" != "major" ]]; then BUMP="minor"; fi
    elif [[ "$line" =~ $RE_FIX ]]; then
      FIXES+=("$(clean_desc "$line")")
      if [[ "$BUMP" == "none" ]]; then BUMP="patch"; fi
    fi
  done < "$file"
  return 0
}

# --- version arithmetic -----------------------------------------------------

bump_version() {
  local ver="$1" type="$2" major minor patch
  IFS='.' read -r major minor patch <<< "$ver"
  case "$type" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    none)  : ;;                      # version stays the same
    *)     die "unknown bump type: $type" ;;
  esac
  printf '%d.%d.%d' "$major" "$minor" "$patch"
}

# --- changelog generation ---------------------------------------------------

# generate_changelog: build the new entry from the classified commits and
# prepend it to the changelog file (creating it with a title if absent).
generate_changelog() {
  local new="$1" file="$2" date="$3" tmp d
  tmp=$(mktemp)
  {
    printf '## [%s] - %s\n\n' "$new" "$date"
    if ((${#BREAKING[@]})); then
      printf '### ⚠ BREAKING CHANGES\n\n'
      for d in "${BREAKING[@]}"; do printf -- '- %s\n' "$d"; done
      printf '\n'
    fi
    if ((${#FEATS[@]})); then
      printf '### Features\n\n'
      for d in "${FEATS[@]}"; do printf -- '- %s\n' "$d"; done
      printf '\n'
    fi
    if ((${#FIXES[@]})); then
      printf '### Bug Fixes\n\n'
      for d in "${FIXES[@]}"; do printf -- '- %s\n' "$d"; done
      printf '\n'
    fi
  } > "$tmp"

  if [[ -f "$file" ]]; then
    cat "$tmp" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    { printf '# Changelog\n\n'; cat "$tmp"; } > "$file"
  fi
  rm -f "$tmp"
}

# --- GitHub Actions integration --------------------------------------------

emit_outputs() {
  local old="$1" new="$2" bump="$3"
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  {
    printf 'old_version=%s\n' "$old"
    printf 'new_version=%s\n' "$new"
    printf 'bump=%s\n' "$bump"
  } >> "$GITHUB_OUTPUT"
}

# --- main -------------------------------------------------------------------

main() {
  local version_file="VERSION" commits_file="" changelog_file="CHANGELOG.md"
  local dry_run=0
  local release_date="${SEMVER_RELEASE_DATE:-$(date +%Y-%m-%d)}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-file) version_file="${2:?--version-file requires an argument}"; shift 2 ;;
      --commits)      commits_file="${2:?--commits requires an argument}";      shift 2 ;;
      --changelog)    changelog_file="${2:?--changelog requires an argument}";  shift 2 ;;
      --date)         release_date="${2:?--date requires an argument}";         shift 2 ;;
      --dry-run)      dry_run=1; shift ;;
      -h|--help)      usage; exit 0 ;;
      *)              die "unknown argument: $1 (use --help)" ;;
    esac
  done

  [[ -n "$commits_file" ]]   || { usage; die "missing required --commits <file>"; }
  [[ -f "$version_file" ]]   || die "version file not found: $version_file"
  [[ -f "$commits_file" ]]   || die "commits file not found: $commits_file"

  local old new
  old=$(read_version "$version_file")
  parse_commits "$commits_file"          # sets BUMP / BREAKING / FEATS / FIXES
  new=$(bump_version "$old" "$BUMP")

  log "Current version: $old"
  log "Detected bump:   $BUMP"
  log "New version:     $new"

  if [[ "$BUMP" == "none" ]]; then
    log "No release-worthy commits (feat/fix/breaking) found; version unchanged."
  elif [[ "$dry_run" -eq 1 ]]; then
    log "Dry-run: not modifying files."
  else
    write_version "$version_file" "$new"
    generate_changelog "$new" "$changelog_file" "$release_date"
    log "Updated $version_file and prepended an entry to $changelog_file."
  fi

  emit_outputs "$old" "$new" "$BUMP"
  printf '%s\n' "$new"                    # <-- the ONLY thing on STDOUT
}

main "$@"
