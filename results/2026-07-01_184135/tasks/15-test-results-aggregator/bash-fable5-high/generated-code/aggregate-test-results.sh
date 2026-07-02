#!/usr/bin/env bash
# aggregate-test-results.sh — aggregate JUnit XML and JSON test results
# across multiple files (e.g. shards of a matrix build) and emit a
# markdown summary suitable for a GitHub Actions job summary.

set -euo pipefail

# Force the C locale so printf/awk always use '.' as the decimal separator —
# duration formatting must be deterministic across environments.
export LC_ALL=C

usage() {
  cat >&2 <<'EOF'
Usage: aggregate-test-results.sh [-o OUTPUT_FILE] RESULTS_DIR

Aggregates all *.xml (JUnit) and *.json test result files found in
RESULTS_DIR, computes totals and flaky tests, and writes a markdown
summary to OUTPUT_FILE (default: stdout).
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# parse_junit_xml FILE
#
# Normalizes a JUnit XML report into TSV records on stdout:
#   run_id <TAB> test_id <TAB> status <TAB> duration
#
# Approach: we deliberately avoid xmllint/xmlstarlet (not present in minimal
# CI containers). Instead we put every XML tag on its own line (tr+sed) and
# run a small awk state machine over the tags:
#   <testcase ...>   opens a case (default status: passed)
#   <failure|error>  marks the open case failed
#   <skipped>        marks the open case skipped
#   /> or </testcase> emits the record
# This handles both self-closing and nested testcase elements regardless of
# attribute order.
parse_junit_xml() {
  local file="$1"
  local run_id
  run_id="$(basename "$file")"
  [[ -r "$file" ]] || die "cannot read file '$file'"
  if ! grep -Eq '<(testsuites?|testcase)[ >/]' "$file"; then
    die "'$file' is not a JUnit XML file (no <testsuite>/<testcase> element found)"
  fi
  tr '\n' ' ' <"$file" | sed 's/</\n</g' | awk -v run="$run_id" '
    # Extract attribute value: match " name=\"...\"" (leading whitespace
    # required so that name= does not also match classname=).
    function attr(a,   m) {
      if (match($0, "[ \t]" a "=\"[^\"]*\"")) {
        m = substr($0, RSTART, RLENGTH)
        sub(/^[^"]*"/, "", m)
        sub(/"$/, "", m)
        return m
      }
      return ""
    }
    function emit(   id) {
      id = (cls != "") ? cls "." nm : nm
      # %.3f normalizes durations (e.g. "0.5" -> 0.500) so downstream
      # assertions do not depend on how the producer formatted numbers.
      printf "%s\t%s\t%s\t%.3f\n", run, id, st, (tm == "") ? 0 : tm + 0
      open = 0
    }
    /^<testcase[ \t>]/ {
      cls = attr("classname"); nm = attr("name"); tm = attr("time")
      st = "passed"; open = 1
      # Self-closing testcase has no children: emit immediately.
      if ($0 ~ /\/>/) emit()
      next
    }
    open && /^<(failure|error)[ \t>/]/ { st = "failed"; next }
    open && /^<skipped[ \t>/]/         { st = "skipped"; next }
    open && /^<\/testcase>/            { emit() }
  '
}

# parse_json_results FILE
#
# Normalizes a JSON test report into the same TSV records as parse_junit_xml.
# Expected schema: {"suite": "...", "tests": [{"name","status","duration"}]}
# where "name" is the fully-qualified test id (e.g. "ui.test_click") and
# "status" is one of passed|failed|skipped.
parse_json_results() {
  local file="$1"
  local run_id
  run_id="$(basename "$file")"
  [[ -r "$file" ]] || die "cannot read file '$file'"
  # Validate before extracting so users get one clear error, not a jq trace.
  if ! jq empty "$file" >/dev/null 2>&1; then
    die "'$file' contains invalid JSON"
  fi
  if ! jq -e '.tests | type == "array"' "$file" >/dev/null 2>&1; then
    die "'$file' is missing a 'tests' array"
  fi
  if ! jq -e 'all(.tests[]; (.name | type == "string") and (.status | type == "string"))' \
      "$file" >/dev/null 2>&1; then
    die "'$file' has test entries missing a 'name' or 'status' string"
  fi
  # jq extracts the fields; awk normalizes the duration (jq 1.6 and 1.7
  # format floats differently, so we never rely on jq's number rendering).
  jq -r '.tests[] | [.name, .status, (.duration // 0)] | @tsv' "$file" |
    awk -F'\t' -v run="$run_id" -v file="$file" '
      $2 != "passed" && $2 != "failed" && $2 != "skipped" {
        printf "ERROR: %s: unknown status \"%s\" for test \"%s\" (expected passed|failed|skipped)\n", \
          file, $2, $1 | "cat >&2"
        exit 1
      }
      { printf "%s\t%s\t%s\t%.3f\n", run, $1, $2, $3 + 0 }
    '
}

# collect_records DIR
#
# Runs the right parser for every *.xml / *.json file in DIR (one file per
# matrix run/shard) and concatenates the normalized records. Files are
# processed in sorted order so output is deterministic.
collect_records() {
  local dir="$1"
  [[ -d "$dir" ]] || die "'$dir' is not a directory"
  local -a files=()
  local f
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f \( -name '*.xml' -o -name '*.json' \) | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    die "no test result files (*.xml, *.json) found in '$dir'"
  fi
  for f in "${files[@]}"; do
    case "$f" in
      *.xml) parse_junit_xml "$f" ;;
      *.json) parse_json_results "$f" ;;
    esac
  done
}

# compute_totals
#
# Reads normalized records on stdin; prints one TSV line:
#   total <TAB> passed <TAB> failed <TAB> skipped <TAB> duration
compute_totals() {
  awk -F'\t' '
    { total++; dur += $4 }
    $3 == "passed"  { p++ }
    $3 == "failed"  { f++ }
    $3 == "skipped" { s++ }
    END { printf "%d\t%d\t%d\t%d\t%.2f\n", total, p, f, s, dur }
  '
}

# find_flaky_tests
#
# Reads normalized records on stdin. A test is flaky when it PASSED in at
# least one run and FAILED in at least one other run of the same matrix.
# Prints TSV lines: test_id <TAB> passed_count <TAB> failed_count (sorted).
find_flaky_tests() {
  awk -F'\t' '
    $3 == "passed" { pass[$2]++ }
    $3 == "failed" { fail[$2]++ }
    END {
      for (t in pass)
        if (t in fail) printf "%s\t%d\t%d\n", t, pass[t], fail[t]
    }
  ' | sort
}

# generate_markdown
#
# Reads normalized records on stdin and writes the full markdown summary
# (GitHub-flavored, suitable for $GITHUB_STEP_SUMMARY) to stdout.
generate_markdown() {
  local records totals flaky failed_rows nfiles
  local total passed failed skipped duration
  records="$(cat)"
  totals="$(compute_totals <<<"$records")"
  IFS=$'\t' read -r total passed failed skipped duration <<<"$totals"
  flaky="$(find_flaky_tests <<<"$records")"
  # Failed-tests table rows: which test failed in which run.
  failed_rows="$(awk -F'\t' '$3 == "failed" { printf "| `%s` | %s |\n", $2, $1 }' <<<"$records" | sort)"
  nfiles="$(cut -f1 <<<"$records" | sort -u | wc -l)"

  cat <<EOF
# 🧪 Test Results Summary

Aggregated **${nfiles}** result file(s) across the matrix.

| Metric | Value |
| ------ | ----- |
| Total tests | ${total} |
| ✅ Passed | ${passed} |
| ❌ Failed | ${failed} |
| ⏭️ Skipped | ${skipped} |
| ⏱️ Duration | ${duration}s |

## ⚠️ Flaky Tests
EOF

  if [[ -n "$flaky" ]]; then
    cat <<'EOF'

Tests that passed in some runs but failed in others:

| Test | Passed runs | Failed runs |
| ---- | ----------- | ----------- |
EOF
    awk -F'\t' '{ printf "| `%s` | %s | %s |\n", $1, $2, $3 }' <<<"$flaky"
  else
    printf '\n✅ No flaky tests detected.\n'
  fi

  printf '\n## ❌ Failed Tests\n'
  if [[ -n "$failed_rows" ]]; then
    printf '\n| Test | Run |\n| ---- | --- |\n%s\n' "$failed_rows"
  else
    printf '\n✅ No failed tests.\n'
  fi
}

main() {
  local output=""
  while getopts ":o:h" opt; do
    case "$opt" in
      o) output="$OPTARG" ;;
      h) usage; exit 0 ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi

  local results_dir="$1"
  [[ -d "$results_dir" ]] || die "'$results_dir' is not a directory"

  # collect_records dies with a meaningful message on any malformed input;
  # set -e propagates the failure through the command substitution.
  local records summary
  records="$(collect_records "$results_dir")"
  summary="$(generate_markdown <<<"$records")"

  if [[ -n "$output" ]]; then
    printf '%s\n' "$summary" >"$output"
    echo "Summary written to $output" >&2
  else
    printf '%s\n' "$summary"
  fi
}

# Only run main when executed directly, so tests can source the functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
