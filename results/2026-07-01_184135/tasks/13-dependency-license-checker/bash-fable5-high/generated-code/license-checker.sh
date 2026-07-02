#!/usr/bin/env bash
#
# license-checker.sh — dependency license compliance checker.
#
# Parses a dependency manifest (package.json or requirements.txt), looks up
# each dependency's license in a license database file (a mock of a real
# registry lookup, injected for testability), classifies each license
# against an allow-list / deny-list config, and prints a compliance report.
#
# Exit codes:
#   0 - report generated, no denied licenses found
#   1 - report generated, at least one denied license found
#   2 - usage or input error

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: license-checker.sh --manifest FILE --config FILE --license-db FILE

Options:
  --manifest FILE    Dependency manifest (package.json or requirements.txt)
  --config FILE      License policy: lines of allow=<LICENSE> / deny=<LICENSE>
  --license-db FILE  TSV file mapping <dependency>\t<license> (mock lookup)
  -h, --help         Show this help
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

# Parse a pip requirements.txt. Emits one "name<TAB>version" line per
# dependency. Skips blank lines and comments; strips inline comments.
# Pinned versions (==) and range specifiers (>=, ~=, ...) both yield the
# version number; a bare package name yields "*".
parse_pip_manifest() {
  local manifest="$1" raw line name version
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%%#*}"                        # strip inline comment
    line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"  # trim trailing whitespace
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9._-]+)[[:space:]]*(==|\>=|\<=|~=|!=|\>|\<)[[:space:]]*([^,[:space:]]+) ]]; then
      name="${BASH_REMATCH[1]}"
      version="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ ^([A-Za-z0-9._-]+)$ ]]; then
      name="${BASH_REMATCH[1]}"
      version="*"
    else
      die "cannot parse requirements line: '$line' in $manifest"
    fi
    printf '%s\t%s\n' "$name" "$version"
  done < "$manifest"
}

# Parse a package.json with jq. Emits "name<TAB>version-spec" for every
# entry in dependencies and devDependencies, preserving document order.
parse_npm_manifest() {
  local manifest="$1"
  command -v jq >/dev/null 2>&1 || die "jq is required to parse package.json but was not found"
  jq empty "$manifest" 2>/dev/null || die "invalid JSON in manifest: $manifest"
  jq -r '((.dependencies // {}) + (.devDependencies // {}))
         | to_entries[] | "\(.key)\t\(.value)"' "$manifest"
}

# Dispatch to the right parser for the detected manifest type.
parse_manifest() {
  local manifest_type="$1" manifest="$2"
  case "$manifest_type" in
    pip) parse_pip_manifest "$manifest" ;;
    npm) parse_npm_manifest "$manifest" ;;
    *)   die "internal error: no parser for manifest type '$manifest_type'" ;;
  esac
}

# Load the license policy config into two global arrays, ALLOW_LICENSES
# and DENY_LICENSES. Lines look like "allow=MIT" or "deny=GPL-3.0";
# blank lines and '#' comments are ignored, anything else is an error.
ALLOW_LICENSES=()
DENY_LICENSES=()
load_config() {
  local config="$1" raw line
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      allow=?*) ALLOW_LICENSES+=("${line#allow=}") ;;
      deny=?*)  DENY_LICENSES+=("${line#deny=}") ;;
      *)        die "invalid config line: '$line' in $config (expected allow=<LICENSE> or deny=<LICENSE>)" ;;
    esac
  done < "$config"
}

# Look up a dependency's license in the license database (TSV of
# "name<TAB>license"). This file stands in for a real registry query,
# which makes the lookup fully mockable in tests. Prints "UNKNOWN"
# when the dependency is not in the database.
lookup_license() {
  local name="$1" db="$2" license
  license="$(awk -F '\t' -v pkg="$name" '$1 == pkg { print $2; exit }' "$db")"
  printf '%s\n' "${license:-UNKNOWN}"
}

# Classify a license against the loaded policy:
# deny-list wins over allow-list; anything unlisted is "unknown".
classify_license() {
  local license="$1" l
  for l in "${DENY_LICENSES[@]}"; do
    [[ "$license" == "$l" ]] && { echo "denied"; return; }
  done
  for l in "${ALLOW_LICENSES[@]}"; do
    [[ "$license" == "$l" ]] && { echo "approved"; return; }
  done
  echo "unknown"
}

# Build the compliance report: one TSV row per dependency plus a summary
# and an overall PASS/FAIL verdict. Returns 1 if any dependency's license
# is denied, 0 otherwise.
generate_report() {
  local manifest_type="$1" manifest="$2" license_db="$3"
  local parsed name version license status
  local total=0 approved=0 denied=0 unknown=0

  # Parse first so a parse error aborts before any report output.
  parsed="$(parse_manifest "$manifest_type" "$manifest")"

  echo "DEPENDENCY LICENSE COMPLIANCE REPORT"
  echo "manifest: $manifest ($manifest_type)"
  printf 'name\tversion\tlicense\tstatus\n'

  while IFS=$'\t' read -r name version; do
    [[ -z "$name" ]] && continue
    license="$(lookup_license "$name" "$license_db")"
    status="$(classify_license "$license")"
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$license" "$status"
    total=$((total + 1))
    case "$status" in
      approved) approved=$((approved + 1)) ;;
      denied)   denied=$((denied + 1)) ;;
      unknown)  unknown=$((unknown + 1)) ;;
    esac
  done <<< "$parsed"

  echo "SUMMARY: total=$total approved=$approved denied=$denied unknown=$unknown"
  if [[ "$denied" -gt 0 ]]; then
    echo "RESULT: FAIL"
    return 1
  fi
  echo "RESULT: PASS"
  return 0
}

# Decide manifest type from the file name: "npm" for package.json,
# "pip" for requirements*.txt. Anything else is unsupported.
detect_manifest_type() {
  local manifest="$1"
  case "$(basename "$manifest")" in
    package.json)      echo "npm" ;;
    requirements*.txt) echo "pip" ;;
    *)
      die "unsupported manifest type: $(basename "$manifest") (expected package.json or requirements.txt)"
      ;;
  esac
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 2
  fi

  local manifest="" config="" license_db="" parse_only=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)   manifest="${2:-}"; shift 2 ;;
      --config)     config="${2:-}"; shift 2 ;;
      --license-db) license_db="${2:-}"; shift 2 ;;
      --parse-only) parse_only=1; shift ;;
      -h|--help)    usage; exit 0 ;;
      *)            usage; die "unknown option: $1" ;;
    esac
  done

  # Validate all inputs up front so the user gets one clear error.
  [[ -n "$manifest" ]]   || die "--manifest is required"
  [[ -n "$config" ]]     || die "--config is required"
  [[ -n "$license_db" ]] || die "--license-db is required"
  [[ -f "$manifest" ]]   || die "manifest file not found: $manifest"
  [[ -f "$config" ]]     || die "config file not found: $config"
  [[ -f "$license_db" ]] || die "license db file not found: $license_db"

  local manifest_type
  manifest_type="$(detect_manifest_type "$manifest")"

  if [[ "$parse_only" -eq 1 ]]; then
    parse_manifest "$manifest_type" "$manifest"
    exit 0
  fi

  load_config "$config"
  # generate_report returns 1 on denied licenses; propagate that as the
  # script's exit code without tripping `set -e`.
  local rc=0
  generate_report "$manifest_type" "$manifest" "$license_db" || rc=$?
  exit "$rc"
}

main "$@"
