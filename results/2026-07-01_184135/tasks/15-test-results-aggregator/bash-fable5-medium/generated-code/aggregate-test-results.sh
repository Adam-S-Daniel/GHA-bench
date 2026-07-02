#!/usr/bin/env bash
# =============================================================================
# aggregate-test-results.sh
#
# Aggregates test results across multiple result files (simulating a matrix
# build), supporting two input formats:
#   *.xml  — JUnit XML  (<testcase> with optional <failure>/<error>/<skipped>)
#   *.json — JSON       ({"tests": [{"classname","name","status","duration"}]})
#
# It computes totals (passed / failed / skipped / duration), identifies flaky
# tests (tests that passed in some runs and failed in others), lists
# consistently failing tests, and emits a markdown summary suitable for a
# GitHub Actions job summary ($GITHUB_STEP_SUMMARY).
#
# Approach:
#   1. Each parser normalizes one file into TSV lines: "id<TAB>status<TAB>secs"
#      where id = classname.name. This gives one uniform intermediate format,
#      so aggregation logic is independent of input formats.
#   2. A single awk pass over the TSV computes totals and per-test pass/fail
#      tallies, then prints the markdown report.
#
# Usage: aggregate-test-results.sh <results-dir> [output-file]
#   <results-dir>  directory containing *.xml / *.json result files
#   [output-file]  optional path to also write the markdown summary to
#                  (the summary is always printed to stdout)
# =============================================================================
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $(basename "$0") <results-dir> [output-file]" >&2
  exit 2
}

# --- Parsers ----------------------------------------------------------------

# Normalize one JUnit XML file to TSV: id<TAB>status<TAB>duration
# Pure awk parser: split the document on "<testcase", inspect each chunk's
# attribute list (up to the first ">") for name/classname/time, and its body
# (up to "</testcase>") for <failure>/<error>/<skipped> children.
parse_junit_xml() {
  local file="$1"
  grep -q '<testsuite' "$file" || die "$file: not a JUnit XML file (no <testsuite> element)"
  awk '
    BEGIN { RS = "<testcase"; }
    NR > 1 {
      chunk = $0
      gt = index(chunk, ">")
      if (gt == 0) next
      attrs = substr(chunk, 1, gt - 1)
      # Self-closing <testcase ... /> has no body
      if (attrs ~ /\/[[:space:]]*$/) body = ""
      else { body = substr(chunk, gt + 1); sub(/<\/testcase>.*/, "", body) }

      name = ""; classname = ""; time = "0"
      if (match(attrs, /[[:space:]]name="[^"]*"/)) {
        name = substr(attrs, RSTART, RLENGTH)
        sub(/^[[:space:]]name="/, "", name); sub(/"$/, "", name)
      }
      if (match(attrs, /classname="[^"]*"/)) {
        classname = substr(attrs, RSTART + 11, RLENGTH - 12)
      }
      if (match(attrs, /time="[^"]*"/)) {
        time = substr(attrs, RSTART + 6, RLENGTH - 7)
      }
      status = "passed"
      if (body ~ /<(failure|error)[ \/>]/) status = "failed"
      else if (body ~ /<skipped[ \/>]/)   status = "skipped"

      id = (classname != "") ? classname "." name : name
      printf "%s\t%s\t%s\n", id, status, time
    }
  ' "$file"
}

# Normalize one JSON result file to TSV: id<TAB>status<TAB>duration
parse_json() {
  local file="$1"
  jq -e . "$file" > /dev/null 2>&1 || die "$file: invalid JSON"
  jq -e '.tests | type == "array"' "$file" > /dev/null 2>&1 \
    || die "$file: invalid JSON schema (expected top-level \"tests\" array)"
  jq -r '
    .tests[]
    | [ (if .classname and .classname != "" then .classname + "." + .name else .name end),
        (.status // "unknown"),
        (.duration // 0) ]
    | @tsv
  ' "$file"
}

# --- Aggregation + markdown report -------------------------------------------

# Reads TSV records on stdin and prints the markdown summary.
render_markdown() {
  awk -F '\t' '
    {
      total++
      dur += $3
      if ($2 == "passed")       { passed++; pass_runs[$1]++ }
      else if ($2 == "failed")  { failed++; fail_runs[$1]++ }
      else if ($2 == "skipped") { skipped++ }
      else { unknown++ }
    }
    END {
      print "# Test Results Summary"
      print ""
      print "| Metric | Count |"
      print "| --- | --- |"
      printf "| Total | %d |\n",   total
      printf "| Passed | %d |\n",  passed
      printf "| Failed | %d |\n",  failed
      printf "| Skipped | %d |\n", skipped
      printf "| Duration | %.2fs |\n", dur

      # Flaky = passed in at least one run AND failed in at least one run
      print ""
      print "## Flaky Tests"
      print ""
      nflaky = 0
      for (id in pass_runs) {
        if (id in fail_runs) {
          printf "- ⚠️ `%s` — passed %d, failed %d\n", id, pass_runs[id], fail_runs[id]
          nflaky++
        }
      }
      if (nflaky == 0) print "No flaky tests detected. ✅"

      # Consistently failing = failed at least once and never passed
      print ""
      print "## Failed Tests"
      print ""
      nfail = 0
      for (id in fail_runs) {
        if (!(id in pass_runs)) {
          printf "- ❌ `%s` — failed %d time(s)\n", id, fail_runs[id]
          nfail++
        }
      }
      if (nfail == 0) print "No consistently failing tests. ✅"
    }
  '
}

# --- Main --------------------------------------------------------------------

main() {
  [ $# -ge 1 ] || usage
  local results_dir="$1"
  local output_file="${2:-}"

  command -v jq > /dev/null 2>&1 || die "jq is required but not installed"
  [ -d "$results_dir" ] || die "'$results_dir' is not a directory"

  # Collect result files deterministically (sorted for stable output)
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$results_dir" -maxdepth 1 -type f \( -name '*.xml' -o -name '*.json' \) | sort)

  [ ${#files[@]} -gt 0 ] || die "no test result files (*.xml, *.json) found in '$results_dir'"

  # Normalize every file into the shared TSV intermediate format
  local tsv=""
  local f records
  for f in "${files[@]}"; do
    case "$f" in
      *.xml)  records="$(parse_junit_xml "$f")" ;;
      *.json) records="$(parse_json "$f")" ;;
    esac
    [ -n "$records" ] && tsv+="$records"$'\n'
  done

  [ -n "$tsv" ] || die "result files contained no test cases"

  local summary
  summary="$(printf '%s' "$tsv" | render_markdown)"

  echo "$summary"
  if [ -n "$output_file" ]; then
    echo "$summary" > "$output_file" \
      || die "cannot write output file '$output_file'"
  fi
}

main "$@"
