#!/usr/bin/env bash
# license_lookup.sh - license lookup (mockable via LICENSE_DB_FILE) and
# allow/deny classification against a license-config.json.

# lookup_license <package-name>
# In production this would hit a registry API; for testing it is fully
# mocked by pointing LICENSE_DB_FILE at a JSON file of {"pkg": "LICENSE"}.
lookup_license() {
  local pkg="$1"
  local db="${LICENSE_DB_FILE:-}"
  if [ -z "$db" ] || [ ! -f "$db" ]; then
    echo "Error: license database not found: ${db:-<unset LICENSE_DB_FILE>}" >&2
    return 1
  fi
  jq -r --arg pkg "$pkg" '.[$pkg] // "UNKNOWN"' "$db"
}

# classify_license <license> <config-file>
# Prints "approved", "denied", or "unknown".
classify_license() {
  local license="$1"
  local config="$2"
  if [ ! -f "$config" ]; then
    echo "Error: license config not found: $config" >&2
    return 1
  fi
  local is_denied is_allowed
  is_denied=$(jq -r --arg lic "$license" '(.deny // []) | index($lic) != null' "$config")
  is_allowed=$(jq -r --arg lic "$license" '(.allow // []) | index($lic) != null' "$config")
  if [ "$is_denied" = "true" ]; then
    echo "denied"
  elif [ "$is_allowed" = "true" ]; then
    echo "approved"
  else
    echo "unknown"
  fi
}
