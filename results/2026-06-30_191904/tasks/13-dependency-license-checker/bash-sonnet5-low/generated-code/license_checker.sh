#!/usr/bin/env bash
# license_checker.sh - Dependency license compliance checker.
#
# Parses a dependency manifest (package.json or requirements.txt), looks up
# each dependency's license (mockable via --license-db / LICENSE_DB_FILE),
# classifies it against an allow/deny list, and prints a CSV compliance
# report: name,version,license,status
#
# Exit codes:
#   0 - report generated, no denied licenses found
#   1 - usage error or missing input file
#   2 - report generated, but at least one dependency uses a denied license

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/manifest_parser.sh
source "$SCRIPT_DIR/lib/manifest_parser.sh"
# shellcheck source=lib/license_lookup.sh
source "$SCRIPT_DIR/lib/license_lookup.sh"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") --manifest <file> --config <license-config.json> [--license-db <file>]

  --manifest <file>     Path to package.json or requirements.txt
  --config <file>       Path to JSON file with "allow" and "deny" license arrays
  --license-db <file>   Path to a mock license database JSON (name -> license)
                        Overrides the LICENSE_DB_FILE environment variable.
EOF
}

main() {
  local manifest="" config="" license_db="${LICENSE_DB_FILE:-}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="$2"; shift 2 ;;
      --config) config="$2"; shift 2 ;;
      --license-db) license_db="$2"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "Error: unknown argument: $1" >&2; usage; return 1 ;;
    esac
  done

  if [ -z "$manifest" ] || [ -z "$config" ]; then
    echo "Error: --manifest and --config are required" >&2
    usage
    return 1
  fi

  if [ ! -f "$manifest" ]; then
    echo "Error: manifest file not found: $manifest" >&2
    return 1
  fi
  if [ ! -f "$config" ]; then
    echo "Error: license config file not found: $config" >&2
    return 1
  fi

  export LICENSE_DB_FILE="$license_db"

  local deps
  if ! deps="$(parse_manifest "$manifest")"; then
    echo "Error: failed to parse manifest: $manifest" >&2
    return 1
  fi

  echo "name,version,license,status"
  local any_denied=0
  local name version license status
  while IFS=' ' read -r name version; do
    [ -z "$name" ] && continue
    license="$(lookup_license "$name")"
    status="$(classify_license "$license" "$config")"
    echo "${name},${version},${license},${status}"
    if [ "$status" = "denied" ]; then
      any_denied=1
    fi
  done <<< "$deps"

  if [ "$any_denied" -eq 1 ]; then
    return 2
  fi
  return 0
}

main "$@"
