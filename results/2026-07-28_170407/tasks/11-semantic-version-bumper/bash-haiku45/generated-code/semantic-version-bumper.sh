#!/usr/bin/env bash
# Semantic version bumper - parses version, determines next version based on commits,
# updates version file, and generates changelog

set -euo pipefail

# Validate that a string is a valid semantic version (MAJOR.MINOR.PATCH)
validate_semver() {
  local version=$1
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 1
  fi
  return 0
}

# Parse version from version.txt or package.json
# Arguments: $1 = path to version file
# Returns: semantic version string
# Exit codes: 0 on success, 1 on error
parse_version() {
  local file=$1

  if [ ! -f "$file" ]; then
    echo "Error: Version file not found: $file" >&2
    return 1
  fi

  local version
  if [[ "$file" == *.json ]]; then
    # Extract version from package.json using grep and sed
    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | sed 's/.*"\([^"]*\)".*/\1/')
  else
    # Read version from version.txt (first line)
    version=$(head -n 1 "$file" | xargs)
  fi

  if ! validate_semver "$version"; then
    echo "Error: Invalid semantic version format: $version" >&2
    return 1
  fi

  echo "$version"
}

# Update version in a version file (version.txt or package.json)
# Arguments: $1 = path to version file, $2 = new version
# Exit codes: 0 on success, 1 on error
update_version() {
  local file=$1
  local new_version=$2

  if [ ! -f "$file" ]; then
    echo "Error: Version file not found: $file" >&2
    return 1
  fi

  if [[ "$file" == *.json ]]; then
    # Update package.json version field
    sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$new_version\"/" "$file"
  else
    # Update version.txt (replace first line)
    local temp_file="${file}.tmp"
    {
      echo "$new_version"
      tail -n +2 "$file"
    } > "$temp_file"
    mv "$temp_file" "$file"
  fi
}

# Generate a changelog from commits between two revisions
# Arguments: $1 = base revision, $2 = head revision
# Returns: formatted changelog entries
generate_changelog() {
  local base=$1
  local head=$2

  # Get commit messages and their types
  git log --pretty=format:"%B|END|" "$base..$head" 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^(feat|fix|chore|docs|style|refactor|perf|test):\ (.*) ]]; then
      local msg="${BASH_REMATCH[2]}"
      echo "- $msg"
    fi
  done

  # Include breaking changes in changelog
  if git log --format=%B "$base..$head" 2>/dev/null | grep -q "BREAKING CHANGE"; then
    echo ""
    echo "BREAKING CHANGES:"
    git log --format=%B "$base..$head" 2>/dev/null | grep -A2 "^BREAKING CHANGE" | grep -v "^BREAKING CHANGE" | grep -v "^--$" | sed 's/^/- /'
  fi
}

# Calculate the next version based on bump type
# Arguments: $1 = current version, $2 = bump type (major|minor|patch|none)
# Returns: next semantic version
# Exit codes: 0 on success, 1 on error
next_version() {
  local current=$1
  local bump_type=$2

  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"

  case "$bump_type" in
    major)
      ((major++))
      minor=0
      patch=0
      ;;
    minor)
      ((minor++))
      patch=0
      ;;
    patch)
      ((patch++))
      ;;
    none)
      # No version change
      ;;
    *)
      echo "Error: Invalid bump type: $bump_type" >&2
      return 1
      ;;
  esac

  echo "$major.$minor.$patch"
}

# Determine the bump type based on commits between two revisions
# Arguments: $1 = base revision, $2 = head revision
# Returns: "major" (breaking), "minor" (feat), "patch" (fix), or "none"
determine_bump() {
  local base=$1
  local head=$2

  # Collect all commit messages between base and head
  local messages
  messages=$(git log --format=%B "$base..$head" 2>/dev/null || echo "")

  # Check for breaking changes first (highest priority)
  if echo "$messages" | grep -q "BREAKING CHANGE"; then
    echo "major"
    return 0
  fi

  # Check for features (minor)
  if echo "$messages" | grep -q "^feat"; then
    echo "minor"
    return 0
  fi

  # Check for fixes (patch)
  if echo "$messages" | grep -q "^fix"; then
    echo "patch"
    return 0
  fi

  # No conventional commits found
  echo "none"
  return 0
}

# Main function
main() {
  # Script body will be added incrementally
  :
}

# Run main if sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
