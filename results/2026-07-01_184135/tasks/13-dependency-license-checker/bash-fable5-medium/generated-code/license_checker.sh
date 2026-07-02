#!/usr/bin/env bash
# license_checker.sh — dependency license compliance checker.
#
# Approach (built via red/green TDD, see test/license_checker.bats):
#   1. Parse a dependency manifest (package.json or requirements.txt)
#      into simple "name version" lines.
#   2. Look up each dependency's license in a license database file.
#      In tests/CI the database is a MOCK fixture, standing in for a
#      real registry lookup, which keeps the checker deterministic.
#   3. Classify each license against an allow-list / deny-list config.
#   4. Emit a compliance report with per-dependency status
#      (approved / denied / unknown) plus a summary line.
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# parse_manifest <file>
# Emits one "name version" line per dependency. The manifest type is
# detected from the filename: *.json -> package.json, otherwise
# requirements.txt style is assumed.
parse_manifest() {
  local manifest=$1
  [ -f "$manifest" ] || die "manifest not found: $manifest"
  case "$manifest" in
    *.json)
      command -v jq >/dev/null 2>&1 || die "jq is required to parse JSON manifests"
      # Merge dependencies + devDependencies, preserving key order.
      jq -er '((.dependencies // {}) + (.devDependencies // {}))
              | to_entries[] | "\(.key) \(.value)"' "$manifest" \
        || die "failed to parse JSON manifest: $manifest"
      ;;
    *)
      # requirements.txt style: "name==version", ignoring comments/blanks.
      grep -vE '^\s*(#|$)' "$manifest" \
        | sed -nE 's/^\s*([A-Za-z0-9._-]+)\s*==\s*([A-Za-z0-9._-]+)\s*$/\1 \2/p'
      ;;
  esac
}

# lookup_license <name> <db>
# The db is a "name license" line-per-entry file; in tests it is a mock
# standing in for a registry query. Prints UNKNOWN when not found.
lookup_license() {
  local name=$1 db=$2 license
  [ -f "$db" ] || die "license database not found: $db"
  license=$(awk -v n="$name" '$1 == n { print $2; exit }' "$db")
  echo "${license:-UNKNOWN}"
}

# classify_license <license> <policy>
# Policy file has "allow: X" / "deny: X" lines. Deny wins over allow,
# so a license on both lists is treated as denied (safe default).
classify_license() {
  local license=$1 policy=$2
  [ -f "$policy" ] || die "policy config not found: $policy"
  if grep -qE "^\s*deny:\s*${license}\s*$" "$policy"; then
    echo "denied"
  elif grep -qE "^\s*allow:\s*${license}\s*$" "$policy"; then
    echo "approved"
  else
    echo "unknown"
  fi
}

# generate_report [--strict] <manifest> <policy> <db>
# Prints the compliance report. With --strict, exits 2 if any
# dependency has a denied license (useful as a CI gate).
generate_report() {
  local strict=0
  if [ "${1:-}" = "--strict" ]; then
    strict=1
    shift
  fi
  local manifest=$1 policy=$2 db=$3
  local name version license status
  local total=0 approved=0 denied=0 unknown=0

  echo "Dependency License Compliance Report"
  echo "manifest: $manifest"
  echo "------------------------------------"
  while read -r name version; do
    [ -n "$name" ] || continue
    license=$(lookup_license "$name" "$db")
    status=$(classify_license "$license" "$policy")
    echo "$name $version $license $status"
    total=$((total + 1))
    case "$status" in
      approved) approved=$((approved + 1)) ;;
      denied) denied=$((denied + 1)) ;;
      *) unknown=$((unknown + 1)) ;;
    esac
  done < <(parse_manifest "$manifest")
  echo "------------------------------------"
  echo "SUMMARY: total=$total approved=$approved denied=$denied unknown=$unknown"

  if [ "$strict" -eq 1 ] && [ "$denied" -gt 0 ]; then
    echo "ERROR: $denied denied license(s) found" >&2
    return 2
  fi
}

usage() {
  cat <<EOF
Usage: $0 <command> [args]
  parse <manifest>                          print "name version" per dependency
  lookup <name> <db>                        print a dependency's license
  classify <license> <policy>               print approved|denied|unknown
  report [--strict] <manifest> <policy> <db>  full compliance report
EOF
}

main() {
  local cmd=${1:-}
  case "$cmd" in
    parse)
      parse_manifest "${2:?usage: $0 parse <manifest>}"
      ;;
    lookup)
      lookup_license "${2:?usage: $0 lookup <name> <db>}" "${3:?missing db}"
      ;;
    classify)
      classify_license "${2:?usage: $0 classify <license> <policy>}" "${3:?missing policy}"
      ;;
    report)
      shift
      generate_report "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      die "unknown command: '$cmd'"
      ;;
  esac
}

main "$@"
