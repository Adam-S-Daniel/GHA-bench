#!/usr/bin/env bash
#
# aggregate.sh — Test Results Aggregator
#
# Parses test result files in JUnit XML and JSON formats, aggregates results
# across multiple files (e.g. a CI matrix build), computes totals
# (passed / failed / skipped / duration), identifies flaky tests (tests that
# passed in some runs and failed in others), and renders a Markdown summary
# suitable for a GitHub Actions job summary ($GITHUB_STEP_SUMMARY).
#
# Usage:
#   aggregate.sh <file-or-dir> [<file-or-dir> ...]
#
#   - Arguments may be individual .xml / .json files or directories. A directory
#     is scanned (non-recursively) for *.xml and *.json files.
#   - The Markdown report is written to stdout.
#
# Design notes:
#   - Every parser normalizes each test case into a single pipe-delimited
#     record:  status|test_id|duration
#       status   = passed | failed | skipped
#       test_id  = "classname.name" (or just "name" when no classname)
#       duration = seconds (float)
#   - Aggregation/flaky-detection/markdown rendering all operate on this common
#     record stream, so adding a new input format only means adding a parser.
#
# The script exits 0 on a successful report even if tests failed — it is a
# *reporter*, not a gate. Use the rendered "Result" line (or grep the output)
# to decide whether a downstream step should fail.

set -o errexit
set -o nounset
set -o pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# err: print a message to stderr.
err() {
  printf 'Error: %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: aggregate.sh <file-or-dir> [<file-or-dir> ...]

Parse JUnit XML and/or JSON test result files, aggregate them, detect flaky
tests, and print a Markdown summary to stdout.

Options:
  -h, --help    Show this help and exit.
EOF
}

# ---------------------------------------------------------------------------
# Parsers — each emits "status|test_id|duration" lines on stdout.
# ---------------------------------------------------------------------------

# parse_junit_xml <file>
# Parse a JUnit XML file. Handles both self-closing <testcase .../> elements
# and <testcase ...> ... </testcase> elements containing <failure>, <error>
# or <skipped> children. No XML library is required (xmllint is not available
# in the act container), so we flatten newlines and use PCRE grep.
parse_junit_xml() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    err "file not found: $file"
    return 1
  fi

  local content
  content=$(tr '\n' ' ' < "$file")

  # Extract each <testcase> element (self-closing OR with a body). The PCRE
  # non-greedy match keeps each element separate.
  local tc
  while IFS= read -r tc; do
    [[ -n "$tc" ]] || continue

    local classname name time status id
    classname=$(grep -oP 'classname="\K[^"]*' <<<"$tc" | head -n1 || true)
    name=$(grep -oP '\bname="\K[^"]*' <<<"$tc" | head -n1 || true)
    time=$(grep -oP '\btime="\K[^"]*' <<<"$tc" | head -n1 || true)
    [[ -n "$time" ]] || time="0"

    # A <failure> or <error> child => failed; <skipped> => skipped; else passed.
    if grep -qP '<failure[ />]|<error[ />]' <<<"$tc"; then
      status="failed"
    elif grep -qP '<skipped[ />]' <<<"$tc"; then
      status="skipped"
    else
      status="passed"
    fi

    if [[ -n "$classname" ]]; then
      id="${classname}.${name}"
    else
      id="$name"
    fi

    printf '%s|%s|%s\n' "$status" "$id" "$time"
  done < <(grep -oP '<testcase\b[^>]*/>|<testcase\b[^>]*>.*?</testcase>' <<<"$content" || true)
}

# parse_json <file>
# Parse a JSON test result file of the form:
#   { "tests": [ { "classname": "...", "name": "...",
#                  "status": "passed|failed|skipped", "duration": 0.0 }, ... ] }
# classname and duration are optional.
parse_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    err "file not found: $file"
    return 1
  fi

  if ! jq -e 'has("tests") and (.tests | type == "array")' "$file" >/dev/null 2>&1; then
    err "invalid or unrecognized JSON test format: $file (expected a top-level \"tests\" array)"
    return 1
  fi

  jq -r '
    .tests[]
    | ((.status // "passed") | ascii_downcase) as $st
    | (if (.classname // "") != "" then (.classname + "." + .name) else .name end) as $id
    | "\($st)|\($id)|\(.duration // 0)"
  ' "$file"
}

# parse_file <file>
# Dispatch to the correct parser based on file extension.
parse_file() {
  local file="$1"
  case "$file" in
    *.xml)  parse_junit_xml "$file" ;;
    *.json) parse_json "$file" ;;
    *)
      err "unsupported file type (expected .xml or .json): $file"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Aggregation + Markdown rendering
# ---------------------------------------------------------------------------

# generate_markdown
# Reads "status|test_id|duration" records on stdin and writes a Markdown
# summary to stdout. Computes totals and detects flaky tests (an id seen both
# passed and failed across runs).
generate_markdown() {
  awk -F'|' '
    {
      status = $1; id = $2; dur = $3 + 0
      total++
      duration += dur
      if      (status == "passed")  passed++
      else if (status == "failed")  failed++
      else if (status == "skipped") skipped++
      else                          unknown++

      seen[id, status] = 1
      if (!(id in idfirst)) { idfirst[id] = ++norder; order[norder] = id }
    }
    END {
      # Collect flaky test ids in first-seen order.
      flaky_n = 0
      for (i = 1; i <= norder; i++) {
        id = order[i]
        if (((id, "passed") in seen) && ((id, "failed") in seen)) {
          flaky_n++
          flaky[flaky_n] = id
        }
      }

      printf "## Test Results Summary\n\n"
      printf "| Metric | Value |\n"
      printf "| --- | --- |\n"
      printf "| Passed | %d |\n", passed
      printf "| Failed | %d |\n", failed
      printf "| Skipped | %d |\n", skipped
      printf "| Total | %d |\n", total
      printf "| Flaky | %d |\n", flaky_n
      printf "| Duration | %.2fs |\n", duration
      printf "\n"

      printf "### Flaky Tests\n\n"
      if (flaky_n == 0) {
        printf "None detected. \xE2\x9C\x85\n\n"
      } else {
        printf "%d test(s) passed in some runs and failed in others:\n\n", flaky_n
        for (i = 1; i <= flaky_n; i++) {
          printf "- `%s`\n", flaky[i]
        }
        printf "\n"
      }

      if (failed > 0) {
        printf "**Result:** FAILED \xE2\x9D\x8C\n"
      } else {
        printf "**Result:** PASSED \xE2\x9C\x85\n"
      }
    }
  '
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do paths+=("$1"); shift; done
        break
        ;;
      -*)
        err "unknown option: $1"
        usage >&2
        return 1
        ;;
      *)
        paths+=("$1")
        ;;
    esac
    shift
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    err "no input files or directories provided"
    usage >&2
    return 1
  fi

  # Expand directories into the .xml/.json files they contain.
  local files=() p f
  for p in "${paths[@]}"; do
    if [[ -d "$p" ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
      done < <(find "$p" -maxdepth 1 -type f \( -name '*.xml' -o -name '*.json' \) | sort)
    elif [[ -f "$p" ]]; then
      files+=("$p")
    else
      err "path not found: $p"
      return 1
    fi
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    err "no .xml or .json test result files found in the given path(s)"
    return 1
  fi

  # Parse every file into the common record stream, then render once.
  local records
  records=$(for f in "${files[@]}"; do parse_file "$f"; done)

  printf '%s\n' "$records" | generate_markdown
}

# Only run main when executed directly, so tests can `source` this file and
# call individual functions in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
