#!/usr/bin/env bash
# bump_version.sh — semantic version bumper driven by conventional commits.
#
# Reads a current version from a version file (plain "VERSION" text file or
# package.json), inspects a log of commit subject lines for conventional
# commit prefixes (feat/fix/breaking), computes the next semantic version,
# rewrites the version file, appends a changelog entry, and prints the
# result. Designed to be called from a CI pipeline (see
# .github/workflows/semantic-version-bumper.yml) but works standalone too.
#
# Usage:
#   bump_version.sh <version-file> <commits-file> [changelog-file]
#
# Exit codes:
#   0  success (version bumped, or no bump needed)
#   1  usage / input error (missing file, unparsable version, etc.)
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

# die MESSAGE — print a usage-style error to stderr and exit non-zero.
die() {
    echo "${SCRIPT_NAME}: error: $1" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <version-file> <commits-file> [changelog-file]

  version-file    Path to a VERSION file (bare "X.Y.Z") or a package.json
                   containing a top-level "version" field.
  commits-file    Path to a file with one commit per line (git log --oneline
                   style: "<sha> <subject>", or just "<subject>").
  changelog-file  Path to the changelog to update (default: CHANGELOG.md,
                   created if missing).
EOF
}

# is_valid_semver VERSION — true if VERSION matches X.Y.Z (non-negative ints).
is_valid_semver() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# read_version FILE — print the semantic version found in FILE.
# Supports a bare VERSION text file and a package.json with a "version" key.
read_version() {
    local file=$1 raw
    case "$file" in
        *.json)
            raw=$(grep -m1 -E '"version"[[:space:]]*:' "$file" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/') \
                || die "could not find a \"version\" field in $file"
            ;;
        *)
            raw=$(head -n1 "$file" | tr -d '[:space:]')
            ;;
    esac
    [[ -n "$raw" ]] || die "version file $file did not contain a version string"
    is_valid_semver "$raw" || die "'$raw' in $file is not a valid semantic version (expected X.Y.Z)"
    printf '%s' "$raw"
}

# write_version FILE VERSION — rewrite FILE in place with the new VERSION.
write_version() {
    local file=$1 version=$2
    case "$file" in
        *.json)
            # Replace only the first "version" occurrence (the package's own
            # top-level field), leaving any nested fields untouched.
            sed -E "0,/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s//\"version\": \"${version}\"/" \
                "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            ;;
        *)
            printf '%s\n' "$version" > "$file"
            ;;
    esac
}

# classify_commit_line LINE — echo "breaking", "feat", "fix", or "none" for
# a single commit line, stripping a leading git-log-style commit hash.
classify_commit_line() {
    local line=$1 subject
    local breaking_re='^[a-zA-Z]+(\([^)]*\))?!:'
    local feat_re='^feat(\([^)]*\))?:'
    local fix_re='^fix(\([^)]*\))?:'

    # Strip a leading "<sha> " if present (git log --oneline format).
    if [[ $line =~ ^[0-9a-f]{7,40}[[:space:]]+(.*)$ ]]; then
        subject=${BASH_REMATCH[1]}
    else
        subject=$line
    fi

    if [[ $subject =~ $breaking_re ]] || [[ $subject == *"BREAKING CHANGE"* ]] || [[ $subject == *"BREAKING-CHANGE"* ]]; then
        echo "breaking"
    elif [[ $subject =~ $feat_re ]]; then
        echo "feat"
    elif [[ $subject =~ $fix_re ]]; then
        echo "fix"
    else
        echo "none"
    fi
}

# determine_bump COMMITS_FILE — echo the highest-priority bump level found
# across all commit lines: "major" > "minor" > "patch" > "none".
determine_bump() {
    local commits_file=$1 level highest="none" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line// }" ]] && continue
        level=$(classify_commit_line "$line")
        case "$level" in
            breaking) highest="major" ;;
            feat) [[ "$highest" != "major" ]] && highest="minor" ;;
            fix) [[ "$highest" == "none" ]] && highest="patch" ;;
        esac
    done < "$commits_file"
    echo "$highest"
}

# bump_version_string VERSION LEVEL — echo the next semantic version.
bump_version_string() {
    local version=$1 level=$2 major minor patch
    IFS='.' read -r major minor patch <<< "$version"
    case "$level" in
        major) printf '%d.%d.%d' "$((major + 1))" 0 0 ;;
        minor) printf '%d.%d.%d' "$major" "$((minor + 1))" 0 ;;
        patch) printf '%d.%d.%d' "$major" "$minor" "$((patch + 1))" ;;
        *) printf '%s' "$version" ;;
    esac
}

# changelog_section COMMITS_FILE LEVEL — echo the grouped, human-readable
# body (Features / Bug Fixes / BREAKING CHANGES) for the changelog entry.
changelog_section() {
    local commits_file=$1 line subject level
    local -a breaking=() feats=() fixes=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line// }" ]] && continue
        if [[ $line =~ ^[0-9a-f]{7,40}[[:space:]]+(.*)$ ]]; then
            subject=${BASH_REMATCH[1]}
        else
            subject=$line
        fi
        level=$(classify_commit_line "$line")
        case "$level" in
            breaking) breaking+=("$subject") ;;
            feat) feats+=("$subject") ;;
            fix) fixes+=("$subject") ;;
        esac
    done < "$commits_file"

    if [[ ${#breaking[@]} -gt 0 ]]; then
        echo "### BREAKING CHANGES"
        for subject in "${breaking[@]}"; do echo "- ${subject}"; done
        echo
    fi
    if [[ ${#feats[@]} -gt 0 ]]; then
        echo "### Features"
        for subject in "${feats[@]}"; do echo "- ${subject}"; done
        echo
    fi
    if [[ ${#fixes[@]} -gt 0 ]]; then
        echo "### Bug Fixes"
        for subject in "${fixes[@]}"; do echo "- ${subject}"; done
        echo
    fi
}

# write_changelog CHANGELOG_FILE NEW_VERSION COMMITS_FILE LEVEL — prepend a
# new entry to CHANGELOG_FILE (creating it with a title if it doesn't exist).
write_changelog() {
    local changelog_file=$1 new_version=$2 commits_file=$3 level=$4
    local entry tmp
    entry=$(
        printf '## %s (%s)\n\n' "$new_version" "$level"
        changelog_section "$commits_file" "$level"
    )
    tmp=$(mktemp)
    if [[ -f "$changelog_file" ]]; then
        {
            head -n1 "$changelog_file" | grep -q '^# ' && head -n1 "$changelog_file" || echo "# Changelog"
            echo
            printf '%s\n' "$entry"
            if head -n1 "$changelog_file" | grep -q '^# '; then
                tail -n +2 "$changelog_file"
            else
                cat "$changelog_file"
            fi
        } > "$tmp"
    else
        {
            echo "# Changelog"
            echo
            printf '%s\n' "$entry"
        } > "$tmp"
    fi
    mv "$tmp" "$changelog_file"
}

main() {
    [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; die "expected 2 or 3 arguments, got $#"; }

    local version_file=$1 commits_file=$2 changelog_file=${3:-CHANGELOG.md}
    [[ -f "$version_file" ]] || die "version file not found: $version_file"
    [[ -f "$commits_file" ]] || die "commits file not found: $commits_file"

    local current_version bump_level new_version
    current_version=$(read_version "$version_file")
    bump_level=$(determine_bump "$commits_file")

    if [[ "$bump_level" == "none" ]]; then
        echo "Current version: ${current_version}"
        echo "Bump type: none"
        echo "New version: ${current_version}"
        echo "No version-impacting commits found; version left unchanged." >&2
    else
        new_version=$(bump_version_string "$current_version" "$bump_level")
        write_version "$version_file" "$new_version"
        write_changelog "$changelog_file" "$new_version" "$commits_file" "$bump_level"
        echo "Current version: ${current_version}"
        echo "Bump type: ${bump_level}"
        echo "New version: ${new_version}"
    fi

    # Expose results to GitHub Actions when running as a step, without
    # requiring the caller to be CI-aware.
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "current_version=${current_version}"
            echo "bump_type=${bump_level}"
            echo "new_version=${new_version:-$current_version}"
        } >> "$GITHUB_OUTPUT"
    fi
}

main "$@"
