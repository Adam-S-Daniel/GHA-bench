#!/usr/bin/env bash
# Parses a JUnit XML file into normalized TSV rows: file<TAB>testname<TAB>status<TAB>duration
#
# Rationale: no XML tool is guaranteed to be on the runner, but JUnit XML from a
# given generator is very regular. Rather than write a general XML parser (fragile
# and overkill), we exploit the known shape of our fixtures: one <testcase .../> or
# <testcase ...>...</testcase> per line-ish block, each optionally containing a
# <failure> or <skipped> child. We use awk to walk testcase blocks and classify
# status by scanning for those child tags between the open and close of each testcase.
#
# Limitation: this assumes each testcase's opening tag and attributes do not span
# unusual multi-line attribute formatting beyond what our generator produces, and
# that <failure>/<skipped> tags appear on their own line(s) within the testcase body.

set -euo pipefail

die() {
  echo "parse_junit: $*" >&2
  exit 1
}

main() {
  local file="${1:-}"
  [ -n "$file" ] || die "no input file given"
  [ -f "$file" ] || die "file not found: $file"

  # Minimal well-formedness check: every <testcase opening tag must have a matching
  # close (either self-closing '/>' or a later '</testcase>'). This catches the
  # "unclosed tag" malformed fixture without needing a real XML parser.
  local opens closes selfclosed
  opens=$(grep -c '<testcase ' "$file" || true)
  closes=$(grep -c '</testcase>' "$file" || true)
  selfclosed=$(grep -c '<testcase[^>]*/>' "$file" || true)
  if [ "$((closes + selfclosed))" -lt "$opens" ]; then
    die "malformed XML in $file: unclosed <testcase> element"
  fi

  local base
  base=$(basename "$file")

  awk -v base="$base" '
    BEGIN { in_case=0; name=""; time=""; status=""; body="" }
    /<testcase / {
      in_case=1
      body=$0
      # Match `name="` but not the `name="` suffix of `classname="`, since both
      # attributes are present on the same testcase line.
      name=$0; sub(/.*[^s]name="/, "", name); sub(/".*/, "", name)
      time=$0; sub(/.*time="/, "", time); sub(/".*/, "", time)
      status="passed"
      if ($0 ~ /<\/testcase>/) {
        if ($0 ~ /<failure/) status="failed"
        if ($0 ~ /<skipped/) status="skipped"
        print base "\t" name "\t" status "\t" time
        in_case=0
      } else if ($0 ~ /\/>[[:space:]]*$/) {
        print base "\t" name "\t" status "\t" time
        in_case=0
      }
      next
    }
    in_case && /<failure/ { status="failed" }
    in_case && /<skipped/ { status="skipped" }
    in_case && /<\/testcase>/ {
      print base "\t" name "\t" status "\t" time
      in_case=0
      next
    }
  ' "$file"
}

main "$@"
