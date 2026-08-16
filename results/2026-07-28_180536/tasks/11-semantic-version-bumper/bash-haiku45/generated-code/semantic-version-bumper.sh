#!/usr/bin/env bash

# Semantic version bumper: parses versions, determines next version from commits,
# updates version files, and generates changelog entries.
#
# Approach:
# 1. Parse semantic versions (with optional v prefix)
# 2. Analyze git commits since last tag/version
# 3. Apply conventional commit rules: feat=minor, fix=patch, breaking=major
# 4. Update version in files (package.json or VERSION)
# 5. Generate changelog entries

set -o pipefail

# Print error message and exit
error() {
  echo "ERROR: $*" >&2
  exit 1
}

# Validate semantic version format
validate_version() {
  local version="$1"
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 1
  fi
  return 0
}

# Parse version from file (strips v prefix if present)
parse_version() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    error "File not found: $file"
  fi

  local version

  if [[ "$file" == *.json ]]; then
    # Parse from package.json
    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*' "$file" | cut -d'"' -f4)
  else
    # Parse from VERSION or similar plain text file
    version=$(head -n1 "$file" | tr -d '[:space:]')
  fi

  # Strip v prefix if present
  version="${version#v}"

  # Validate format
  if ! validate_version "$version"; then
    error "Invalid version format in $file: $version"
  fi

  echo "$version"
}

# Get current git tag or use provided version
get_current_version_tag() {
  local version_file="$1"
  local current_version

  current_version=$(parse_version "$version_file")

  # Try to find matching git tag
  if git rev-parse "v${current_version}" >/dev/null 2>&1; then
    echo "v${current_version}"
  elif git rev-parse "${current_version}" >/dev/null 2>&1; then
    echo "${current_version}"
  else
    # No tag exists, use HEAD~1 or HEAD
    if git rev-parse HEAD >/dev/null 2>&1; then
      # If we have commits, use the commit before the version file was last updated
      # For now, we'll use a marker based on the current version
      echo "base"
    fi
  fi
}

# Extract commit type from conventional commit message
get_commit_type() {
  local message="$1"

  if [[ $message =~ ^[a-z]+!: ]]; then
    echo "breaking"
  elif [[ $message =~ ^feat ]]; then
    echo "feat"
  elif [[ $message =~ ^fix ]]; then
    echo "fix"
  elif [[ $message =~ ^refactor|^docs|^style|^test|^chore|^perf ]]; then
    echo "other"
  else
    echo "other"
  fi
}

# Get all commits since a certain point
get_commits_since() {
  local from_ref="$1"
  local to_ref="${2:-HEAD}"

  if [[ "$from_ref" == "base" ]]; then
    # Get commits since last version tag or all commits
    git log --pretty=format:"%s" "$to_ref" 2>/dev/null | head -100
  else
    git log --pretty=format:"%s" "${from_ref}..${to_ref}" 2>/dev/null
  fi
}

# Determine the next version based on commits
calculate_next_version() {
  local current_version="$1"
  local version_file="$2"

  local major minor patch
  IFS='.' read -r major minor patch <<<"$current_version"

  local has_breaking=0
  local has_feat=0
  local has_fix=0

  local from_ref
  from_ref=$(get_current_version_tag "$version_file")

  # Get commits and analyze them
  local commits
  commits=$(get_commits_since "$from_ref")

  if [[ -z "$commits" ]]; then
    # No new commits, return current version
    echo "$current_version"
    return 0
  fi

  while IFS= read -r message; do
    [[ -z "$message" ]] && continue

    local commit_type
    commit_type=$(get_commit_type "$message")

    case "$commit_type" in
      breaking)
        has_breaking=1
        ;;
      feat)
        has_feat=1
        ;;
      fix)
        has_fix=1
        ;;
    esac
  done <<<"$commits"

  # Apply semantic versioning rules
  if [[ $has_breaking -eq 1 ]]; then
    ((major++))
    minor=0
    patch=0
  elif [[ $has_feat -eq 1 ]]; then
    ((minor++))
    patch=0
  elif [[ $has_fix -eq 1 ]]; then
    ((patch++))
  fi

  echo "${major}.${minor}.${patch}"
}

# Update version in a file
update_version_in_file() {
  local file="$1"
  local new_version="$2"

  if [[ ! -f "$file" ]]; then
    error "File not found: $file"
  fi

  if [[ "$file" == *.json ]]; then
    # Update package.json
    sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"${new_version}\"/" "$file"
  else
    # Update VERSION file
    echo "$new_version" > "$file"
  fi
}

# Generate changelog entry from commits
generate_changelog() {
  local version_file="$1"
  local new_version="$2"

  local from_ref
  from_ref=$(get_current_version_tag "$version_file")

  # Start changelog
  echo "## [$new_version] - $(date +%Y-%m-%d)"
  echo ""

  local features=()
  local fixes=()
  local breaking=()

  # Categorize commits
  local commits
  commits=$(get_commits_since "$from_ref")

  while IFS= read -r message; do
    [[ -z "$message" ]] && continue

    local commit_type
    commit_type=$(get_commit_type "$message")

    case "$commit_type" in
      breaking)
        breaking+=("$message")
        ;;
      feat)
        # Extract feature description (remove "feat: " prefix)
        features+=("${message#*: }")
        ;;
      fix)
        # Extract fix description (remove "fix: " prefix)
        fixes+=("${message#*: }")
        ;;
    esac
  done <<<"$commits"

  # Print breaking changes
  if [[ ${#breaking[@]} -gt 0 ]]; then
    echo "### ⚠️ BREAKING CHANGES"
    echo ""
    for change in "${breaking[@]}"; do
      echo "- ${change#*: }"
    done
    echo ""
  fi

  # Print features
  if [[ ${#features[@]} -gt 0 ]]; then
    echo "### Features"
    echo ""
    for feature in "${features[@]}"; do
      echo "- $feature"
    done
    echo ""
  fi

  # Print fixes
  if [[ ${#fixes[@]} -gt 0 ]]; then
    echo "### Bug Fixes"
    echo ""
    for fix in "${fixes[@]}"; do
      echo "- $fix"
    done
    echo ""
  fi
}

# Main entry point
main() {
  local action=""
  local version_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --current-version)
        action="current-version"
        version_file="$2"
        shift 2
        ;;
      --next-version)
        action="next-version"
        version_file="$2"
        shift 2
        ;;
      --update)
        action="update"
        version_file="$2"
        shift 2
        ;;
      --changelog)
        action="changelog"
        version_file="$2"
        shift 2
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done

  if [[ -z "$action" ]]; then
    error "No action specified. Use --current-version, --next-version, --update, or --changelog"
  fi

  if [[ -z "$version_file" ]]; then
    error "No version file specified"
  fi

  case "$action" in
    current-version)
      parse_version "$version_file"
      ;;
    next-version)
      local current
      current=$(parse_version "$version_file")
      calculate_next_version "$current" "$version_file"
      ;;
    update)
      local current next
      current=$(parse_version "$version_file")
      next=$(calculate_next_version "$current" "$version_file")
      if [[ "$next" != "$current" ]]; then
        update_version_in_file "$version_file" "$next"
        echo "Updated $version_file from $current to $next"
      fi
      ;;
    changelog)
      local current next
      current=$(parse_version "$version_file")
      next=$(calculate_next_version "$current" "$version_file")
      generate_changelog "$version_file" "$next"
      ;;
  esac
}

main "$@"
