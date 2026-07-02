#!/usr/bin/env bash
# Parses a JSON result file into normalized TSV rows: file<TAB>testname<TAB>status<TAB>duration
#
# Schema (our own, for fixtures): {"tests":[{"name":str,"status":"passed|failed|skipped","duration":number}]}
# We rely on jq rather than hand-rolled JSON parsing since jq is standard on Ubuntu
# CI images and correctly handles quoting/escaping that ad-hoc grep/sed would not.

set -euo pipefail

die() {
  echo "parse_json: $*" >&2
  exit 1
}

main() {
  local file="${1:-}"
  [ -n "$file" ] || die "no input file given"
  [ -f "$file" ] || die "file not found: $file"
  command -v jq >/dev/null 2>&1 || die "jq is required but not found on PATH"

  jq -e . "$file" >/dev/null 2>&1 || die "invalid JSON in $file (failed to parse)"

  local base
  base=$(basename "$file")

  jq -r '.tests[] | [.name, .status, .duration] | @tsv' "$file" \
    | awk -F'\t' -v base="$base" '{ print base "\t" $1 "\t" $2 "\t" $3 }'
}

main "$@"
