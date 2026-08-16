#!/bin/bash

# Semantic Version Bumper
# Parses version files, determines next version based on conventional commits,
# updates version, and generates changelog entries.

set -euo pipefail

# Parse version from package.json or VERSION file
parse_version() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file" >&2
    return 1
  fi

  if [ "$file" = "package.json" ] || [[ "$file" == *.json ]]; then
    # Extract version from package.json using grep and sed
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | sed 's/.*"\([^"]*\)".*/\1/'
  else
    # Assume it's a plain text file with just the version
    head -1 "$file" | tr -d '[:space:]'
  fi
}

# Compare two semantic versions: returns 0 if equal, 1 if v1>v2, -1 if v1<v2
compare_versions() {
  local v1="$1"
  local v2="$2"

  # Split versions into parts
  local IFS='.'
  read -ra parts1 <<< "$v1"
  read -ra parts2 <<< "$v2"

  for i in {0..2}; do
    local p1=${parts1[$i]:-0}
    local p2=${parts2[$i]:-0}

    if [ "$p1" -gt "$p2" ]; then
      echo "1"
      return 0
    elif [ "$p1" -lt "$p2" ]; then
      echo "-1"
      return 0
    fi
  done

  echo "0"
  return 0
}

# Get next version based on conventional commits
# Returns major, minor, or patch
get_next_version() {
  local current_version="$1"
  local bump_type="$2"  # "major", "minor", or "patch"

  IFS='.' read -r major minor patch <<< "$current_version"

  case "$bump_type" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "Error: Unknown bump type: $bump_type" >&2
      return 1
      ;;
  esac

  echo "$major.$minor.$patch"
}

# Analyze commits to determine bump type
# Returns "major", "minor", or "patch"
analyze_commits() {
  local max_bump="patch"

  # Get all commits since the last tag (or all if no tags)
  local commit_log
  if git rev-parse --quiet --verify HEAD > /dev/null 2>&1; then
    commit_log=$(git log --pretty=format:%s --since="1 hour ago" 2>/dev/null || git log --pretty=format:%s 2>/dev/null || true)
  else
    commit_log=""
  fi

  # Check for breaking changes (feat! or BREAKING CHANGE)
  if echo "$commit_log" | grep -E '^[a-z]+!:' > /dev/null 2>&1; then
    max_bump="major"
  elif echo "$commit_log" | grep -i "BREAKING CHANGE" > /dev/null 2>&1; then
    max_bump="major"
  # Check for features (feat:)
  elif echo "$commit_log" | grep '^feat:' > /dev/null 2>&1; then
    if [ "$max_bump" = "patch" ]; then
      max_bump="minor"
    fi
  # Check for fixes (fix:)
  elif echo "$commit_log" | grep '^fix:' > /dev/null 2>&1; then
    if [ "$max_bump" = "patch" ]; then
      max_bump="patch"
    fi
  fi

  echo "$max_bump"
}

# Update version in file
update_version() {
  local file="$1"
  local new_version="$2"

  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file" >&2
    return 1
  fi

  if [ "$file" = "package.json" ] || [[ "$file" == *.json ]]; then
    # Update version in package.json
    if command -v jq > /dev/null 2>&1; then
      jq ".version = \"$new_version\"" "$file" > "${file}.tmp"
      mv "${file}.tmp" "$file"
    else
      # Fallback to sed
      sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$new_version\"/" "$file"
    fi
  else
    # Write plain version to file
    echo "$new_version" > "$file"
  fi
}

# Generate changelog from commits
generate_changelog() {
  local since_tag="${1:---all}"

  # Get commit log with conventional commit format
  local commit_log
  if [ "$since_tag" = "--all" ]; then
    commit_log=$(git log --pretty=format:'%s' 2>/dev/null || true)
  else
    commit_log=$(git log "$since_tag..HEAD" --pretty=format:'%s' 2>/dev/null || true)
  fi

  # Group by type
  local features=$(echo "$commit_log" | grep '^feat:' | sed 's/^feat:[[:space:]]*/- /' || true)
  local fixes=$(echo "$commit_log" | grep '^fix:' | sed 's/^fix:[[:space:]]*/- /' || true)
  local breaking=$(echo "$commit_log" | grep -E '^[a-z]+!:' | sed 's/^[a-z]*!:[[:space:]]*/- BREAKING: /' || true)

  if [ -n "$breaking" ]; then
    echo "### Breaking Changes"
    echo "$breaking"
    echo ""
  fi

  if [ -n "$features" ]; then
    echo "### Features"
    echo "$features"
    echo ""
  fi

  if [ -n "$fixes" ]; then
    echo "### Bug Fixes"
    echo "$fixes"
  fi
}

main() {
  case "${1:-help}" in
    --parse-version)
      parse_version "$2"
      ;;
    --next-version)
      local version_file="$2"
      local current_version=$(parse_version "$version_file")
      local bump_type=$(analyze_commits)
      get_next_version "$current_version" "$bump_type"
      ;;
    --update-version)
      update_version "$2" "$3"
      ;;
    --changelog-from-commits)
      generate_changelog "${2:---all}"
      ;;
    --since-last-tag)
      # Used with --changelog-from-commits
      return 0
      ;;
    help)
      cat << 'EOF'
Semantic Version Bumper

Usage:
  version-bumper.sh --parse-version <file>
  version-bumper.sh --next-version <version-file>
  version-bumper.sh --update-version <file> <new-version>
  version-bumper.sh --changelog-from-commits [--since-last-tag]

Options:
  --parse-version <file>        Extract version from package.json or VERSION file
  --next-version <file>         Determine next version based on commits
  --update-version <file> <ver> Update version in file
  --changelog-from-commits      Generate changelog from commits

Conventional Commits:
  feat:  - Adds a new feature (minor bump)
  fix:   - Fixes a bug (patch bump)
  feat!: - Breaking change (major bump)
EOF
      ;;
    *)
      echo "Error: Unknown command: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
