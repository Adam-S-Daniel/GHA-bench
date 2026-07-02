#!/usr/bin/env bash
# manifest_parser.sh - extract "name version" pairs from dependency manifests.
# Each function prints one "name version" pair per line on stdout.

# Parse a package.json file's "dependencies" object.
parse_package_json() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Error: manifest file not found: $file" >&2
    return 1
  fi
  jq -r '.dependencies // {} | to_entries[] | "\(.key) \(.value)"' "$file"
}

# Parse a requirements.txt file. Supports "==", ">=", "<=", "~=" specifiers.
# Lines that are blank or start with '#' are skipped.
parse_requirements_txt() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Error: manifest file not found: $file" >&2
    return 1
  fi
  local line name version
  while IFS= read -r line; do
    line="$(echo "$line" | sed 's/#.*$//' | sed 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    if [[ "$line" =~ ^([A-Za-z0-9_.-]+)==(.+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^([A-Za-z0-9_.-]+)(>=|<=|~=|>|<)(.+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    else
      name="$line"
      version="unspecified"
      echo "$name $version"
    fi
  done < "$file"
}

# Dispatch to the correct parser based on the manifest filename.
parse_manifest() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Error: manifest file not found: $file" >&2
    return 1
  fi
  case "$(basename "$file")" in
    package.json)
      parse_package_json "$file"
      ;;
    requirements.txt)
      parse_requirements_txt "$file"
      ;;
    *)
      echo "Error: unsupported manifest type: $file" >&2
      return 1
      ;;
  esac
}
