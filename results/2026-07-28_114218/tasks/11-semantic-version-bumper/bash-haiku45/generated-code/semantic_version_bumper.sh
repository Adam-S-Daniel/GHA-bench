#!/usr/bin/env bash

set -euo pipefail

# Semantic Version Bumper
# Bumps version based on conventional commits (feat -> minor, fix -> patch, BREAKING CHANGE -> major)
# Generates changelog entries and updates version files

get_current_version() {
  local version_file="$1"

  if [[ ! -f "$version_file" ]]; then
    echo "Error: version file '$version_file' not found" >&2
    return 1
  fi

  case "$version_file" in
    *.json)
      # Extract version from JSON file
      if ! version=$(grep -o '"version": "[^"]*"' "$version_file" | grep -o '[0-9.]\+' | head -1); then
        echo "Error: invalid JSON or missing version field in '$version_file'" >&2
        return 1
      fi
      echo "$version"
      ;;
    *)
      # Assume plain text file with version on first line
      if [[ ! -s "$version_file" ]]; then
        echo "Error: version file is empty" >&2
        return 1
      fi
      head -1 "$version_file" | grep -o '^[0-9.]\+' || {
        echo "Error: invalid version format in '$version_file'" >&2
        return 1
      }
      ;;
  esac
}

get_major_version() {
  local version="$1"
  echo "$version" | cut -d. -f1
}

get_minor_version() {
  local version="$1"
  echo "$version" | cut -d. -f2
}

get_patch_version() {
  local version="$1"
  echo "$version" | cut -d. -f3
}

bump_version() {
  local version="$1"
  local bump_type="$2"

  local major minor patch
  major=$(get_major_version "$version")
  minor=$(get_minor_version "$version")
  patch=$(get_patch_version "$version")

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
      echo "Error: invalid bump type '$bump_type'" >&2
      return 1
      ;;
  esac

  echo "$major.$minor.$patch"
}

get_commits_since_tag() {
  local tag="$1"

  if ! git rev-parse "$tag" >/dev/null 2>&1; then
    # Tag doesn't exist, return all commits
    git log --pretty=format:"%s" 2>/dev/null || true
    return 0
  fi

  git log "$tag"..HEAD --pretty=format:"%s" 2>/dev/null || true
}

detect_bump_type() {
  local commits
  commits=$(get_commits_since_tag "v$(git describe --tags --abbrev=0 2>/dev/null || echo '0.0.0')")

  local has_breaking=0
  local has_feature=0
  local has_fix=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^feat ]]; then
      has_feature=1
    fi
    if [[ "$line" =~ ^fix ]]; then
      has_fix=1
    fi
  done <<< "$commits"

  # Check for BREAKING CHANGE in commit bodies
  if git log --oneline 2>/dev/null | grep -q "BREAKING CHANGE" || \
     git log --format=%b 2>/dev/null | grep -q "BREAKING CHANGE"; then
    has_breaking=1
  fi

  if [[ $has_breaking -eq 1 ]]; then
    echo "major"
  elif [[ $has_feature -eq 1 ]]; then
    echo "minor"
  elif [[ $has_fix -eq 1 ]]; then
    echo "patch"
  else
    echo "patch"
  fi
}

update_version_in_file() {
  local version_file="$1"
  local new_version="$2"

  case "$version_file" in
    *.json)
      # Update JSON version field using sed (portable)
      sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$new_version\"/" "$version_file"
      rm -f "$version_file.bak"
      ;;
    *)
      # Replace first line with new version
      {
        echo "$new_version"
        tail -n +2 "$version_file" || true
      } > "$version_file.tmp"
      mv "$version_file.tmp" "$version_file"
      ;;
  esac
}

generate_changelog_entry() {
  local new_version="${1:-}"
  local last_tag

  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

  if [[ -z "$last_tag" ]]; then
    last_tag="HEAD^"
  fi

  local commits
  commits=$(get_commits_since_tag "$last_tag")

  local today
  today=$(date +%Y-%m-%d)

  if [[ -n "$new_version" ]]; then
    echo "## [$new_version] - $today"
  else
    echo "## [Unreleased] - $today"
  fi
  echo ""

  # Group commits by type
  local has_features=0
  local has_fixes=0
  local has_breaking=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^feat ]]; then
      if [[ $has_features -eq 0 ]]; then
        echo "### Features"
        has_features=1
      fi
      # Format: "- add login feature" instead of "- feat: add login feature"
      echo "- ${line#feat: }"
    fi
  done <<< "$commits"

  [[ $has_features -eq 1 ]] && echo ""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^fix ]]; then
      if [[ $has_fixes -eq 0 ]]; then
        echo "### Bug Fixes"
        has_fixes=1
      fi
      echo "- ${line#fix: }"
    fi
  done <<< "$commits"

  [[ $has_fixes -eq 1 ]] && echo ""

  # Check for breaking changes in full commit bodies
  if git log --format=%b 2>/dev/null | grep -q "BREAKING CHANGE"; then
    echo "### Breaking Changes"
    git log --format=%b 2>/dev/null | grep -A 1 "BREAKING CHANGE" | head -5 || true
    has_breaking=1
  fi
}

semantic_version_bumper() {
  local version_file="$1"

  # Validate input
  if [[ ! -f "$version_file" ]]; then
    echo "Error: version file '$version_file' not found" >&2
    return 1
  fi

  # Get current version
  local current_version
  if ! current_version=$(get_current_version "$version_file"); then
    return 1
  fi

  # Detect bump type from commits
  local bump_type
  bump_type=$(detect_bump_type)

  # Calculate new version
  local new_version
  new_version=$(bump_version "$current_version" "$bump_type")

  # Update version file
  update_version_in_file "$version_file" "$new_version"

  # Generate changelog entry
  local changelog_entry
  changelog_entry=$(generate_changelog_entry "$new_version")

  # Output results
  echo "$new_version"
  echo ""
  echo "$changelog_entry"

  return 0
}

# Main entry point when script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version_file>"
    echo ""
    echo "Bumps semantic version based on conventional commits."
    echo "Supports package.json and version.txt files."
    exit 1
  fi

  semantic_version_bumper "$1"
fi
