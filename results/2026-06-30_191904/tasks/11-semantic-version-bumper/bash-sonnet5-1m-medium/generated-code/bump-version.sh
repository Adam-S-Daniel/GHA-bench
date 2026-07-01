#!/usr/bin/env bash
# bump-version.sh
#
# Determines the next semantic version from conventional-commit-style commit
# messages, updates a version file (plain text or package.json), and appends
# a changelog entry. Designed to be sourced by bats tests (functions only run
# when this file is executed directly, guarded at the bottom).
set -euo pipefail

# parse_version VERSION
# Splits a "MAJOR.MINOR.PATCH" string into its three components and prints
# them space-separated. Fails on anything that isn't strict X.Y.Z semver.
parse_version() {
    local version="$1"
    if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "parse_version: invalid semantic version: '$version'" >&2
        return 1
    fi
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
}

# determine_bump_type COMMITS_FILE
# Scans conventional-commit messages (one per line) and prints the highest
# priority bump implied by them: "major" (breaking change), "minor" (feat),
# "patch" (fix), or "none" (no releasable change, e.g. docs/chore only).
determine_bump_type() {
    local commits_file="$1"
    if [[ ! -f "$commits_file" ]]; then
        echo "determine_bump_type: commits file not found: '$commits_file'" >&2
        return 1
    fi

    local has_minor=0
    local has_patch=0
    local line
    # Regexes are held in variables (rather than inlined) so bash's [[ =~ ]]
    # parser doesn't choke on the literal parentheses in the pattern.
    local breaking_re='^[a-zA-Z]+(\([^)]*\))?!:'
    local footer_re='^BREAKING CHANGE'
    local feat_re='^feat(\([^)]*\))?:'
    local fix_re='^fix(\([^)]*\))?:'

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Breaking changes: "feat!:"/"fix!:" style, or a "BREAKING CHANGE" footer.
        if [[ "$line" =~ $breaking_re ]] || [[ "$line" =~ $footer_re ]]; then
            echo "major"
            return 0
        elif [[ "$line" =~ $feat_re ]]; then
            has_minor=1
        elif [[ "$line" =~ $fix_re ]]; then
            has_patch=1
        fi
    done < "$commits_file"

    if [[ "$has_minor" -eq 1 ]]; then
        echo "minor"
    elif [[ "$has_patch" -eq 1 ]]; then
        echo "patch"
    else
        echo "none"
    fi
}

# compute_next_version CURRENT_VERSION BUMP_TYPE
# Applies a semver bump (major/minor/patch/none) to CURRENT_VERSION and
# prints the resulting version.
compute_next_version() {
    local current="$1"
    local bump_type="$2"
    local major minor patch

    read -r major minor patch <<< "$(parse_version "$current")"

    case "$bump_type" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "${major}.$((minor + 1)).0"
            ;;
        patch)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
        none)
            echo "${major}.${minor}.${patch}"
            ;;
        *)
            echo "compute_next_version: unknown bump type: '$bump_type'" >&2
            return 1
            ;;
    esac
}

# read_current_version VERSION_FILE
# Reads the current semantic version from either a plain-text version file
# (the whole file content is the version) or a package.json ("version"
# field). Which format is used is inferred from the filename.
read_current_version() {
    local version_file="$1"
    if [[ ! -f "$version_file" ]]; then
        echo "read_current_version: file not found: '$version_file'" >&2
        return 1
    fi

    if [[ "$(basename "$version_file")" == "package.json" ]]; then
        local version
        version="$(grep -m1 '"version"' "$version_file" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
        if [[ -z "$version" ]]; then
            echo "read_current_version: no version field found in '$version_file'" >&2
            return 1
        fi
        echo "$version"
    else
        local content
        content="$(cat "$version_file")"
        echo "${content//[[:space:]]/}"
    fi
}

# write_version VERSION_FILE NEW_VERSION
# Writes NEW_VERSION back to VERSION_FILE, preserving package.json structure
# when applicable.
write_version() {
    local version_file="$1"
    local new_version="$2"

    if [[ "$(basename "$version_file")" == "package.json" ]]; then
        local tmp_file
        tmp_file="$(mktemp)"
        sed -E "s/(\"version\"[[:space:]]*:[[:space:]]*)\"[^\"]+\"/\1\"${new_version}\"/" "$version_file" > "$tmp_file"
        mv "$tmp_file" "$version_file"
    else
        echo "$new_version" > "$version_file"
    fi
}

# generate_changelog_entry NEW_VERSION COMMITS_FILE CHANGELOG_FILE
# Prepends a "## NEW_VERSION" section (with one bullet per commit message)
# to the top of CHANGELOG_FILE, creating it if it doesn't exist yet.
generate_changelog_entry() {
    local new_version="$1"
    local commits_file="$2"
    local changelog_file="$3"

    if [[ ! -f "$commits_file" ]]; then
        echo "generate_changelog_entry: commits file not found: '$commits_file'" >&2
        return 1
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    {
        echo "## ${new_version}"
        echo ""
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            echo "- ${line}"
        done < "$commits_file"
        echo ""
        [[ -f "$changelog_file" ]] && cat "$changelog_file"
    } > "$tmp_file"
    mv "$tmp_file" "$changelog_file"
}

# run_bump VERSION_FILE COMMITS_FILE CHANGELOG_FILE
# Orchestrates a full version bump: reads the current version, determines
# the bump type from commit messages, computes and writes the new version,
# updates the changelog, and prints the new version on success. If no
# releasable commits are found, nothing is written and a nonzero status is
# returned.
run_bump() {
    local version_file="$1"
    local commits_file="$2"
    local changelog_file="$3"

    local current_version bump_type new_version
    current_version="$(read_current_version "$version_file")"
    bump_type="$(determine_bump_type "$commits_file")"

    if [[ "$bump_type" == "none" ]]; then
        echo "run_bump: no releasable commits (feat/fix/breaking) found; skipping bump" >&2
        return 1
    fi

    new_version="$(compute_next_version "$current_version" "$bump_type")"
    write_version "$version_file" "$new_version"
    generate_changelog_entry "$new_version" "$commits_file" "$changelog_file"
    echo "$new_version"
}

# usage
# Prints CLI usage information.
usage() {
    cat <<EOF
Usage: $(basename "$0") --version-file FILE --commits-file FILE [--changelog FILE]

  --version-file FILE   Plain-text version file or package.json (required)
  --commits-file FILE   File with one conventional-commit message per line (required)
  --changelog FILE       Changelog file to prepend the new entry to (default: CHANGELOG.md)
  -h, --help             Show this help
EOF
}

# main ARGS...
# CLI entry point: parses flags and runs the full bump workflow.
main() {
    local version_file=""
    local commits_file=""
    local changelog_file="CHANGELOG.md"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version-file)
                version_file="$2"; shift 2 ;;
            --commits-file)
                commits_file="$2"; shift 2 ;;
            --changelog)
                changelog_file="$2"; shift 2 ;;
            -h|--help)
                usage; return 0 ;;
            *)
                echo "main: unknown argument: '$1'" >&2
                usage >&2
                return 1 ;;
        esac
    done

    if [[ -z "$version_file" || -z "$commits_file" ]]; then
        echo "main: --version-file and --commits-file are required" >&2
        usage >&2
        return 1
    fi

    run_bump "$version_file" "$commits_file" "$changelog_file"
}

# Only run main when executed directly (not when sourced by bats tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
