#!/usr/bin/env bash

set -euo pipefail

# Parse semantic version string into major, minor, patch components
parse_version_string() {
  local version="$1"
  local major minor patch

  IFS='.' read -r major minor patch <<< "$version"
  echo "$major" "$minor" "$patch"
}

# Parse version from VERSION file or package.json in current directory
parse_version() {
  if [ -f "package.json" ]; then
    grep -m 1 '"version"' package.json | sed 's/.*"version": "\([^"]*\)".*/\1/'
  elif [ -f "VERSION" ]; then
    cat VERSION
  else
    echo "Error: No version file found (package.json or VERSION)" >&2
    return 1
  fi
}

# Analyze commits between versions and return bump counts
# Returns: "<major_count> <minor_count> <patch_count>"
analyze_commits() {
  local major_count=0
  local minor_count=0
  local patch_count=0

  # Get all commits - check full messages for BREAKING CHANGE and analyze subjects
  while IFS= read -r commit_hash; do
    if [ -z "$commit_hash" ]; then
      continue
    fi

    # Get full commit message
    local commit_msg
    commit_msg=$(git log -1 --format=%B "$commit_hash" 2>/dev/null || echo "")

    # Check for breaking change in full message
    if echo "$commit_msg" | grep -qi "BREAKING CHANGE"; then
      major_count=$((major_count + 1))
      continue
    fi

    # Get commit subject (first line)
    local subject
    subject=$(git log -1 --format=%s "$commit_hash" 2>/dev/null || echo "")

    # Check for feat
    if echo "$subject" | grep -q "^feat"; then
      minor_count=$((minor_count + 1))
    # Check for fix
    elif echo "$subject" | grep -q "^fix"; then
      patch_count=$((patch_count + 1))
    fi
  done < <(git rev-list --all 2>/dev/null || true)

  echo "$major_count $minor_count $patch_count"
}

# Calculate next semantic version based on commits
calculate_next_version() {
  local current_version="$1"
  local counts
  local major_count minor_count patch_count
  local major minor patch

  counts=$(analyze_commits "$current_version")
  read -r major_count minor_count patch_count <<< "$counts"

  read -r major minor patch <<< "$(parse_version_string "$current_version")"

  # Apply version bumps in priority order: major > minor > patch
  if [ "$major_count" -gt 0 ]; then
    major=$((major + major_count))
    minor=0
    patch=0
  elif [ "$minor_count" -gt 0 ]; then
    minor=$((minor + minor_count))
    patch=0
  elif [ "$patch_count" -gt 0 ]; then
    patch=$((patch + patch_count))
  fi

  echo "${major}.${minor}.${patch}"
}

# Update version in VERSION file or package.json
update_version() {
  local file="$1"
  local new_version="$2"

  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file" >&2
    return 1
  fi

  case "$file" in
    package.json)
      # Use sed to update version in package.json
      sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$new_version\"/" "$file"
      ;;
    VERSION)
      # Simple file overwrite for VERSION
      echo "$new_version" > "$file"
      ;;
    *)
      echo "Error: Unknown file type: $file" >&2
      return 1
      ;;
  esac
}

# Generate changelog entry from commits between versions
generate_changelog() {
  local new_version="$2"
  local output=""

  output+="## [$new_version] - $(date +%Y-%m-%d)"$'\n'

  local sections_feat=""
  local sections_fix=""
  local sections_break=""

  while IFS= read -r commit_hash; do
    if [ -z "$commit_hash" ]; then
      continue
    fi

    # Get full commit message
    local commit_msg
    commit_msg=$(git log -1 --format=%B "$commit_hash" 2>/dev/null || echo "")

    # Get commit subject
    local subject
    subject=$(git log -1 --format=%s "$commit_hash" 2>/dev/null || echo "")

    # Check for breaking change
    if echo "$commit_msg" | grep -qi "BREAKING CHANGE"; then
      sections_break+="- $subject"$'\n'
    # Check for feat
    elif echo "$subject" | grep -q "^feat"; then
      local feat_msg
      feat_msg="${subject#feat: }"
      sections_feat+="- $feat_msg"$'\n'
    # Check for fix
    elif echo "$subject" | grep -q "^fix"; then
      local fix_msg
      fix_msg="${subject#fix: }"
      sections_fix+="- $fix_msg"$'\n'
    fi
  done < <(git rev-list --all 2>/dev/null || true)

  if [ -n "$sections_break" ]; then
    output+=$'\n'"### Breaking Changes"$'\n'"$sections_break"
  fi

  if [ -n "$sections_feat" ]; then
    output+=$'\n'"### Features"$'\n'"$sections_feat"
  fi

  if [ -n "$sections_fix" ]; then
    output+=$'\n'"### Bug Fixes"$'\n'"$sections_fix"
  fi

  echo -n "$output"
}

# Main command handler
main() {
  local command="${1:-}"

  case "$command" in
    parse-version)
      parse_version
      ;;
    calculate-next-version)
      if [ $# -lt 2 ]; then
        echo "Error: calculate-next-version requires current version argument" >&2
        return 1
      fi
      calculate_next_version "$2"
      ;;
    update-version)
      if [ $# -lt 3 ]; then
        echo "Error: update-version requires file and new version arguments" >&2
        return 1
      fi
      update_version "$2" "$3"
      ;;
    generate-changelog)
      if [ $# -lt 3 ]; then
        echo "Error: generate-changelog requires old and new version arguments" >&2
        return 1
      fi
      generate_changelog "$2" "$3"
      ;;
    *)
      echo "Usage: $0 {parse-version|calculate-next-version|update-version|generate-changelog}" >&2
      return 1
      ;;
  esac
}

main "$@"
