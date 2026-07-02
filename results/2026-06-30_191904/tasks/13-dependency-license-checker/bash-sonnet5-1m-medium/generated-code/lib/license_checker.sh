#!/usr/bin/env bash
# license_checker.sh
#
# Library of functions for parsing dependency manifests, looking up licenses
# (mockable for tests), classifying them against an allow/deny config, and
# rendering a compliance report. Meant to be `source`d by a driver script
# or bats test file.

# parse_package_json <path>
# Prints "name<TAB>version" for every entry under dependencies/devDependencies.
parse_package_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Error: package.json not found at '$file'" >&2
    return 1
  fi
  jq -r '
    (.dependencies // {}) as $d |
    (.devDependencies // {}) as $dd |
    ($d + $dd) | to_entries[] | "\(.key)\t\(.value)"
  ' "$file" 2>/dev/null || {
    echo "Error: failed to parse package.json '$file' (invalid JSON?)" >&2
    return 1
  }
}

# parse_requirements_txt <path>
# Prints "name<TAB>version" for each pinned requirement (name==version).
# Lines without a version pin get an empty version field. Comments/blank
# lines are skipped.
parse_requirements_txt() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Error: requirements.txt not found at '$file'" >&2
    return 1
  fi

  local line name version
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                 # strip comments
    line="$(echo "$line" | xargs)"      # trim whitespace
    [[ -z "$line" ]] && continue

    if [[ "$line" == *"=="* ]]; then
      name="${line%%==*}"
      version="${line#*==}"
    elif [[ "$line" == *">="* ]]; then
      name="${line%%>=*}"
      version="${line#*>=}"
    else
      name="$line"
      version=""
    fi
    printf '%s\t%s\n' "$name" "$version"
  done < "$file"
}

# lookup_license <name> <version>
# Resolves the license identifier for a dependency. This is a MOCK lookup:
# it reads from a local JSON "database" (path in $LICENSE_DB_FILE) instead
# of calling a real package registry, keyed on "name@version" first and
# falling back to a bare "name" entry. Prints "UNKNOWN" if neither is found.
lookup_license() {
  local name="$1" version="$2"
  local db="${LICENSE_DB_FILE:-}"

  if [[ -z "$db" || ! -f "$db" ]]; then
    echo "Error: license database file not found at '${db:-<unset>}'" >&2
    return 1
  fi

  local license
  license="$(jq -r --arg key "${name}@${version}" '.[$key] // empty' "$db" 2>/dev/null)"
  if [[ -z "$license" ]]; then
    license="$(jq -r --arg key "$name" '.[$key] // empty' "$db" 2>/dev/null)"
  fi

  if [[ -z "$license" ]]; then
    echo "UNKNOWN"
  else
    echo "$license"
  fi
}

# classify_license <license>
# Prints "approved" if the license is in the allow-list, "denied" if in the
# deny-list, "unknown" otherwise (including for a literal "UNKNOWN" string).
# Config is read from $LICENSE_CONFIG_FILE: {"allow": [...], "deny": [...]}.
classify_license() {
  local license="$1"
  local config="${LICENSE_CONFIG_FILE:-}"

  if [[ -z "$config" || ! -f "$config" ]]; then
    echo "Error: license config file not found at '${config:-<unset>}'" >&2
    return 1
  fi

  if [[ "$license" == "UNKNOWN" ]]; then
    echo "unknown"
    return 0
  fi

  local is_allowed is_denied
  is_allowed="$(jq -r --arg lic "$license" '(.allow // []) | index($lic) != null' "$config" 2>/dev/null)"
  is_denied="$(jq -r --arg lic "$license" '(.deny // []) | index($lic) != null' "$config" 2>/dev/null)"

  if [[ "$is_denied" == "true" ]]; then
    echo "denied"
  elif [[ "$is_allowed" == "true" ]]; then
    echo "approved"
  else
    echo "unknown"
  fi
}

# generate_report <manifest-type> <manifest-path>
# Parses the manifest, looks up (mocked) licenses, classifies each against
# the allow/deny config, and prints "name<TAB>version<TAB>license<TAB>status"
# rows. Returns exit code 3 if any dependency is denied, 0 otherwise.
generate_report() {
  local manifest_type="$1" manifest_path="$2"
  local parsed

  case "$manifest_type" in
    package.json)
      parsed="$(parse_package_json "$manifest_path")" || { echo "$parsed" >&2; return 1; }
      ;;
    requirements.txt)
      parsed="$(parse_requirements_txt "$manifest_path")" || { echo "$parsed" >&2; return 1; }
      ;;
    *)
      echo "Error: unsupported manifest type '$manifest_type'" >&2
      return 1
      ;;
  esac

  local name version license status found_denied=0
  while IFS=$'\t' read -r name version; do
    [[ -z "$name" ]] && continue
    license="$(lookup_license "$name" "$version")" || return 1
    status="$(classify_license "$license")" || return 1
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$license" "$status"
    [[ "$status" == "denied" ]] && found_denied=1
  done <<< "$parsed"

  [[ "$found_denied" -eq 1 ]] && return 3
  return 0
}
