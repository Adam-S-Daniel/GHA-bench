#!/usr/bin/env bash
# check-licenses.sh
#
# CLI entry point for the dependency license compliance checker. Parses a
# dependency manifest (package.json or requirements.txt), looks up each
# dependency's license (mocked via a local JSON "database" for testability),
# classifies each against an allow/deny config, and prints a report.
#
# Exit codes:
#   0 - all dependencies approved or unknown
#   1 - usage/input error (bad args, missing files)
#   3 - one or more dependencies use a denied license
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/license_checker.sh
source "${SCRIPT_DIR}/lib/license_checker.sh"

usage() {
  cat <<'EOF'
Usage: check-licenses.sh --manifest <path> --db <license-db.json> --config <license-config.json>

  --manifest <path>  Path to package.json or requirements.txt
  --db <path>        JSON file mocking a license lookup: {"name": "MIT", ...}
  --config <path>    JSON file with allow/deny lists: {"allow": [...], "deny": [...]}
EOF
}

manifest=""
db=""
config=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    --db) db="$2"; shift 2 ;;
    --config) config="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$manifest" || -z "$db" || -z "$config" ]]; then
  echo "Error: --manifest, --db, and --config are all required" >&2
  usage >&2
  exit 1
fi

# Detect manifest type from filename.
manifest_type=""
case "$(basename "$manifest")" in
  package.json) manifest_type="package.json" ;;
  requirements.txt) manifest_type="requirements.txt" ;;
  *)
    echo "Error: cannot determine manifest type for '$manifest' (expected package.json or requirements.txt)" >&2
    exit 1
    ;;
esac

export LICENSE_DB_FILE="$db"
export LICENSE_CONFIG_FILE="$config"

report_status=0
report="$(generate_report "$manifest_type" "$manifest")" || report_status=$?
if [[ $report_status -ne 0 && $report_status -ne 3 ]]; then
  echo "$report" >&2
  exit "$report_status"
fi

approved=0
denied=0
unknown=0

echo "=== DEPENDENCY LICENSE COMPLIANCE REPORT ==="
echo "Manifest: $manifest"
echo ""
printf '%-25s %-12s %-18s %s\n' "PACKAGE" "VERSION" "LICENSE" "STATUS"

while IFS=$'\t' read -r name version license status; do
  [[ -z "$name" ]] && continue
  printf '%-25s %-12s %-18s %s\n' "$name" "$version" "$license" "$status"
  case "$status" in
    approved) approved=$((approved + 1)) ;;
    denied) denied=$((denied + 1)) ;;
    unknown) unknown=$((unknown + 1)) ;;
  esac
done <<< "$report"

echo ""
echo "--- Summary ---"
echo "Approved: $approved"
echo "Denied: $denied"
echo "Unknown: $unknown"

exit "$report_status"
