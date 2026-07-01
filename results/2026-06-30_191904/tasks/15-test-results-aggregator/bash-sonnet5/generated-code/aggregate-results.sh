#!/usr/bin/env bash
# aggregate-results.sh -- aggregate JUnit XML / JSON test result files
# from a matrix build into totals, flaky-test detection, and a GitHub
# Actions job-summary markdown report.
#
# Usage: aggregate-results.sh RESULT_FILE [RESULT_FILE ...]
#
# Each RESULT_FILE is either a JUnit XML file (*.xml) or a JSON results
# file (*.json -- see fixtures/ for the expected shape). Files are
# treated as independent runs of the same matrix build (e.g. one per
# OS/language-version combination); a test that passes in some runs and
# fails in others is reported as flaky.
#
# The rendered markdown is always printed on stdout. If $GITHUB_STEP_SUMMARY
# is set (as it is inside a GitHub Actions job), the same markdown is also
# appended there so it shows up as the job's summary.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091 source=lib/junit_parser.sh
source "${SCRIPT_DIR}/lib/junit_parser.sh"
# shellcheck disable=SC1091 source=lib/json_parser.sh
source "${SCRIPT_DIR}/lib/json_parser.sh"
# shellcheck disable=SC1091 source=lib/aggregator.sh
source "${SCRIPT_DIR}/lib/aggregator.sh"
# shellcheck disable=SC1091 source=lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

usage() {
  cat <<'EOF'
Usage: aggregate-results.sh RESULT_FILE [RESULT_FILE ...]

Aggregate JUnit XML (*.xml) and JSON (*.json) test result files from a
matrix build, compute pass/fail/skip totals and durations, detect flaky
tests (pass in some runs, fail in others), and print a markdown summary
suitable for a GitHub Actions job summary ($GITHUB_STEP_SUMMARY).
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: no result files given" >&2
    usage >&2
    return 2
  fi
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    return 0
  fi

  local tmp_tsv
  tmp_tsv="$(mktemp)"
  trap 'rm -f "$tmp_tsv"' RETURN

  local file run_id ext
  for file in "$@"; do
    if [[ ! -f "$file" ]]; then
      echo "ERROR: result file not found: $file" >&2
      return 1
    fi
    run_id="$(basename -- "$file")"
    run_id="${run_id%.*}"
    ext="${file##*.}"

    case "$ext" in
      xml)
        parse_junit_xml "$file" "$run_id" >> "$tmp_tsv" || return 1
        ;;
      json)
        parse_json_results "$file" "$run_id" >> "$tmp_tsv" || return 1
        ;;
      *)
        echo "ERROR: unsupported result file extension '.$ext' for '$file' (expected .xml or .json)" >&2
        return 1
        ;;
    esac
  done

  aggregator_reset
  aggregator_ingest_tsv < "$tmp_tsv" || return 1

  local summary
  summary="$(render_markdown_summary)"
  printf '%s\n' "$summary"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
  fi
  return 0
}

main "$@"
exit $?
