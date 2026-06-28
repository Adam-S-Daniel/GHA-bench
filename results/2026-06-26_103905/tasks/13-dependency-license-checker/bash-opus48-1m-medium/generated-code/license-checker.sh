#!/usr/bin/env bash
#
# license-checker.sh
#
# Parse a dependency manifest (package.json or requirements.txt), extract
# dependency names and versions, look up each dependency's license (mockable),
# and classify it against an allow-list / deny-list of licenses. Emits a
# compliance report with one line per dependency:
#
#     <name>@<version> <license> <STATUS>
#
# where STATUS is APPROVED, DENIED, or UNKNOWN.
#
# The script is written so it can be both *sourced* (for unit testing each
# function in isolation) and *executed* (as a CLI). When sourced, only the
# function definitions are loaded; main() runs only on direct execution.

set -o errexit
set -o nounset
set -o pipefail

# --- parse_manifest -------------------------------------------------------
#
# Read a manifest file and print "<name> <version>" lines to stdout, one per
# dependency. Supports package.json (npm) and requirements.txt (pip). The
# version is normalised by stripping common range prefixes (^ ~ = >= <= > <).
#
# Args: $1 = path to manifest file
parse_manifest() {
  local manifest="$1"

  if [[ ! -f "$manifest" ]]; then
    echo "error: manifest not found: $manifest" >&2
    return 1
  fi

  case "$manifest" in
    *package.json)
      # Use jq to read the dependencies object as "name version" pairs.
      jq -r '.dependencies // {} | to_entries[] | "\(.key) \(.value)"' \
        "$manifest" | _normalize_versions
      ;;
    *requirements.txt)
      # requirements.txt lines look like "name==1.2.3" or "name>=1.0".
      # Skip blank lines and comments.
      grep -vE '^\s*(#|$)' "$manifest" \
        | sed -E 's/[[:space:]]*([<>=!~]+)[[:space:]]*/ /' \
        | awk '{print $1, $2}' \
        | _normalize_versions
      ;;
    *)
      echo "error: unsupported manifest type: $manifest" >&2
      return 1
      ;;
  esac
}

# Strip leading range operators from the version field of "name version" lines.
_normalize_versions() {
  sed -E 's/^([^ ]+) [\^~=<>!]*/\1 /'
}

# --- lookup_license -------------------------------------------------------
#
# Mockable license lookup. Reads a license database file with lines of the
# form "<name> <license>" and prints the license for the requested dependency,
# or "UNKNOWN" if the dependency is not listed.
#
# Args: $1 = dependency name, $2 = license database file
lookup_license() {
  local name="$1" db="$2" license

  if [[ ! -f "$db" ]]; then
    echo "error: license database not found: $db" >&2
    return 1
  fi

  # First field-exact match wins. Print only the license (second field).
  license="$(awk -v n="$name" '$1 == n {print $2; exit}' "$db")"
  if [[ -z "$license" ]]; then
    echo "UNKNOWN"
  else
    echo "$license"
  fi
}

# --- classify_license -----------------------------------------------------
#
# Classify a license against an allow-list and a deny-list (each a file with
# one license identifier per line). Deny-list takes precedence over the
# allow-list. Anything not on either list (or already UNKNOWN) is UNKNOWN.
#
# Args: $1 = license, $2 = allow-list file, $3 = deny-list file
classify_license() {
  local license="$1" allow="$2" deny="$3"

  if [[ "$license" == "UNKNOWN" ]]; then
    echo "UNKNOWN"
    return 0
  fi
  if grep -qxF "$license" "$deny" 2>/dev/null; then
    echo "DENIED"
  elif grep -qxF "$license" "$allow" 2>/dev/null; then
    echo "APPROVED"
  else
    echo "UNKNOWN"
  fi
}

# --- generate_report ------------------------------------------------------
#
# Drive the full pipeline: parse the manifest, look up each dependency's
# license, classify it, and print the compliance report. Exits non-zero if
# any dependency is DENIED so the report is CI-friendly.
#
# Args: $1 = manifest, $2 = license db, $3 = allow-list, $4 = deny-list
generate_report() {
  local manifest="$1" db="$2" allow="$3" deny="$4"
  local name version license status
  local denied=0

  echo "Dependency License Compliance Report"
  echo "===================================="

  while read -r name version; do
    [[ -z "$name" ]] && continue
    license="$(lookup_license "$name" "$db")"
    status="$(classify_license "$license" "$allow" "$deny")"
    printf '%s@%s %s %s\n' "$name" "$version" "$license" "$status"
    [[ "$status" == "DENIED" ]] && denied=1
  done < <(parse_manifest "$manifest")

  if [[ "$denied" -eq 1 ]]; then
    echo "RESULT: FAIL (denied licenses found)"
    return 1
  fi
  echo "RESULT: PASS"
  return 0
}

# --- main / CLI -----------------------------------------------------------
usage() {
  cat >&2 <<'USAGE'
Usage: license-checker.sh --manifest FILE --licenses FILE --allow FILE --deny FILE

Options:
  --manifest FILE   dependency manifest (package.json or requirements.txt)
  --licenses FILE   mock license database ("<name> <license>" per line)
  --allow FILE      allow-list of license identifiers (one per line)
  --deny FILE       deny-list of license identifiers (one per line)
  -h, --help        show this help
USAGE
}

main() {
  local manifest="" licenses="" allow="" deny=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest) manifest="$2"; shift 2 ;;
      --licenses) licenses="$2"; shift 2 ;;
      --allow)    allow="$2"; shift 2 ;;
      --deny)     deny="$2"; shift 2 ;;
      -h|--help)  usage; return 0 ;;
      *) echo "error: unknown argument: $1" >&2; usage; return 2 ;;
    esac
  done

  # Validate all required inputs are present and readable.
  local missing=0
  for pair in "manifest:$manifest" "licenses:$licenses" "allow:$allow" "deny:$deny"; do
    local key="${pair%%:*}" val="${pair#*:}"
    if [[ -z "$val" ]]; then
      echo "error: missing required --$key" >&2
      missing=1
    elif [[ ! -f "$val" ]]; then
      echo "error: file for --$key not found: $val" >&2
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    usage
    return 2
  fi

  generate_report "$manifest" "$licenses" "$allow" "$deny"
}

# Only run main when executed directly, not when sourced by the test suite.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
