#!/usr/bin/env bash
#
# aggregate-test-results.sh
# =========================
# Aggregate test results from a matrix build and emit a Markdown summary.
#
# It parses test result files in two formats -- JUnit XML and a simple JSON
# schema -- normalises every test case to a common record, then aggregates
# across *all* files (each file is one matrix leg, e.g. one OS/version combo):
#
#   * totals          : passed / failed / skipped / total counts
#   * duration        : summed wall-clock seconds across every test case
#   * flaky tests     : a test that PASSED in at least one run and FAILED in at
#                       least one other run (an unstable test)
#
# The result is rendered as GitHub-flavoured Markdown, ready to be appended to
# $GITHUB_STEP_SUMMARY in a GitHub Actions job. Optionally it also writes a
# machine-readable key=value "counts" file for downstream steps.
#
# Approach / design notes
# -----------------------
#   * Each parser converts its format into a normalised TSV stream of
#         <status>\t<test-id>\t<duration-seconds>
#     where <status> is one of passed|failed|skipped and <test-id> is a stable
#     identity ("classname.name") used to correlate the same test across runs.
#   * Aggregation and flaky detection happen in a single awk pass over the
#     combined stream (associative arrays keyed by test-id).
#   * JUnit XML is parsed with a portable, dependency-free awk "tag stream"
#     walker (no xmllint required); JSON is parsed with jq.
#
# Usage:
#   aggregate-test-results.sh [options] <path> [<path> ...]
#
# Each <path> is either a result file (*.xml / *.json) or a directory, in which
# case every *.xml and *.json file beneath it is parsed.
#
# Options:
#   -o, --output <file>        Write the Markdown summary to <file> (default: stdout)
#   -c, --counts-file <file>   Also write key=value totals to <file>
#   -t, --title <title>        Heading text (default: "Test Results Summary")
#   -h, --help                 Show this help and exit
#
# Exit codes:
#   0  success
#   1  runtime error (missing path, parse failure, no result files)
#   2  usage error (bad/missing arguments)
#   3  missing dependency (jq, needed only for JSON input)

set -euo pipefail

PROG="${0##*/}"

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

# err <message...> : print an error to stderr, prefixed for grep-ability.
err() { printf '%s: error: %s\n' "$PROG" "$*" >&2; }

# warn <message...> : non-fatal diagnostic to stderr.
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $PROG [options] <path> [<path> ...]

Aggregate JUnit XML and JSON test result files from a matrix build, compute
totals (passed/failed/skipped/duration), detect flaky tests, and emit a
Markdown summary suitable for a GitHub Actions job summary.

Each <path> is a result file (*.xml / *.json) or a directory (all *.xml and
*.json files beneath it are parsed).

Options:
  -o, --output <file>        Write the Markdown summary to <file> (default: stdout)
  -c, --counts-file <file>   Also write key=value totals to <file>
  -t, --title <title>        Heading text (default: "Test Results Summary")
  -h, --help                 Show this help and exit
EOF
}

# require_jq : JSON parsing depends on jq; fail clearly if it is absent.
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required to parse JSON test results but was not found in PATH"
    exit 3
  fi
}

# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

# detect_format <file> : echo "junit" or "json". Decide by extension first,
# then fall back to sniffing the first non-whitespace character of the file.
detect_format() {
  local file="$1" first
  case "$file" in
    *.xml | *.XML) echo "junit"; return 0 ;;
    *.json | *.JSON) echo "json"; return 0 ;;
  esac
  first="$(tr -d '[:space:]\357\273\277' < "$file" | head -c1 || true)"
  case "$first" in
    '<') echo "junit"; return 0 ;;
    '{' | '[') echo "json"; return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Parsers -> normalised TSV: <status>\t<test-id>\t<duration>
# ---------------------------------------------------------------------------

# parse_junit_xml <file>
# Walk the JUnit XML as a stream of tags. A <testcase> is "failed" if it
# contains a <failure> or <error> child, "skipped" if it contains <skipped>,
# otherwise "passed". Self-closing "<testcase .../>" tags are passed. We split
# every tag onto its own line first so the awk logic stays line-oriented and
# works on both gawk and mawk (no gawk-only extensions are used).
parse_junit_xml() {
  local file="$1"
  sed 's/</\n</g' "$file" | awk '
    # attr(line, key): return the value of key="..." in line. The leading
    # whitespace requirement prevents "name" from matching inside "classname".
    function attr(s, key,   re, rest, q) {
      re = "[ \t]" key "[ \t]*=[ \t]*\""
      if (match(s, re)) {
        rest = substr(s, RSTART + RLENGTH)
        q = index(rest, "\"")
        if (q > 0) return substr(rest, 1, q - 1)
      }
      return ""
    }
    function emit(   id) {
      id = (cls == "" ? nm : cls "." nm)
      if (id == "") id = "unknown"
      printf "%s\t%s\t%s\n", st, id, tm
    }
    $0 ~ "^<testcase([ \t>/]|$)" {
      nm  = attr($0, "name")
      cls = attr($0, "classname")
      tm  = attr($0, "time"); if (tm == "") tm = "0"
      st  = "passed"
      incase = 1
      if (index($0, "/>") > 0) { emit(); incase = 0 }
      next
    }
    incase && $0 ~ "^<failure" { st = "failed"; next }
    incase && $0 ~ "^<error"   { st = "failed"; next }
    incase && $0 ~ "^<skipped" { if (st == "passed") st = "skipped"; next }
    incase && $0 ~ "^</testcase" { emit(); incase = 0; next }
  '
}

# parse_json <file>
# Accepts either {"tests":[...]} / {"testcases":[...]} or a bare [...] array.
# Each element: {name|test, classname|suite, status|result, duration|time}.
# Status strings are normalised tolerantly (pass*/ok/success, fail*/err*,
# skip*/pending/ignore).
parse_json() {
  local file="$1"
  require_jq
  jq -r '
    (if type == "array" then . else (.tests // .testcases // []) end)
    | .[]
    | ((.status // .result // .outcome // "") | ascii_downcase) as $s
    | (if   ($s | test("^(pass|ok|success)"))      then "passed"
       elif ($s | test("^(fail|err)"))             then "failed"
       elif ($s | test("^(skip|pending|ignore)"))  then "skipped"
       else $s end) as $norm
    | ((.classname // .suite // "")) as $cls
    | ((.name // .test // "unknown")) as $nm
    | [ $norm,
        (if $cls == "" then $nm else ($cls + "." + $nm) end),
        ((.duration // .time // 0) | tostring)
      ]
    | @tsv
  ' "$file"
}

# ---------------------------------------------------------------------------
# File collection
# ---------------------------------------------------------------------------

# collect_files <path...> : expand files + directories into a sorted, newline
# separated list of result files. Errors on a path that does not exist.
collect_files() {
  local p rc=0
  for p in "$@"; do
    if [ -d "$p" ]; then
      find "$p" -type f \
        \( -name '*.xml' -o -name '*.XML' -o -name '*.json' -o -name '*.JSON' \) \
        | sort
    elif [ -f "$p" ]; then
      printf '%s\n' "$p"
    else
      err "path not found: $p"
      rc=1
    fi
  done
  return "$rc"
}

# ---------------------------------------------------------------------------
# Aggregation: combined TSV on stdin -> structured summary lines on stdout
# ---------------------------------------------------------------------------
aggregate() {
  awk '
    BEGIN { FS = "\t" }
    NF == 0 { next }                      # skip blank lines defensively
    {
      st = $1; id = $2; d = $3 + 0
      dur += d
      ids[id] = 1
      if      (st == "passed")  { passed++;  pass[id]++ }
      else if (st == "failed")  { failed++;  fail[id]++ }
      else if (st == "skipped") { skipped++ }
      else                      { unknown++ }
    }
    END {
      total = passed + failed + skipped + unknown
      printf "PASSED %d\n",   passed + 0
      printf "FAILED %d\n",   failed + 0
      printf "SKIPPED %d\n",  skipped + 0
      printf "UNKNOWN %d\n",  unknown + 0
      printf "TOTAL %d\n",    total + 0
      printf "DURATION %.2f\n", dur + 0
      n = 0
      for (id in ids) {
        if (pass[id] > 0 && fail[id] > 0) {
          # A test that both passed and failed across runs is flaky.
          printf "FLAKY\t%s\t%d\t%d\n", id, pass[id], fail[id]
          n++
        }
      }
      printf "FLAKYCOUNT %d\n", n
    }
  '
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# render <summary> <title> <counts_file>
# Reads the aggregate() summary, writes Markdown on stdout and (if counts_file
# is non-empty) a key=value totals file.
render() {
  local summary="$1" title="$2" counts_file="$3"
  local passed=0 failed=0 skipped=0 unknown=0 total=0 duration="0.00" flaky_count=0
  local -a flaky_rows=()
  local line

  while IFS= read -r line; do
    case "$line" in
      "PASSED "*)     passed="${line#PASSED }" ;;
      "FAILED "*)     failed="${line#FAILED }" ;;
      "SKIPPED "*)    skipped="${line#SKIPPED }" ;;
      "UNKNOWN "*)    unknown="${line#UNKNOWN }" ;;
      "TOTAL "*)      total="${line#TOTAL }" ;;
      "DURATION "*)   duration="${line#DURATION }" ;;
      "FLAKYCOUNT "*) flaky_count="${line#FLAKYCOUNT }" ;;
      "FLAKY"$'\t'*)  flaky_rows+=( "${line#FLAKY$'\t'}" ) ;;
    esac
  done <<< "$summary"

  # Sort flaky rows for deterministic, stable output.
  if [ "${#flaky_rows[@]}" -gt 0 ]; then
    mapfile -t flaky_rows < <(printf '%s\n' "${flaky_rows[@]}" | sort)
  fi

  # ----- Markdown summary -----
  {
    printf '# %s\n\n' "$title"
    printf '| Result | Count |\n'
    printf '| :--- | ---: |\n'
    printf '| Passed | %s |\n' "$passed"
    printf '| Failed | %s |\n' "$failed"
    printf '| Skipped | %s |\n' "$skipped"
    if [ "${unknown:-0}" -gt 0 ]; then
      printf '| Unknown | %s |\n' "$unknown"
    fi
    printf '| **Total** | **%s** |\n' "$total"
    printf '| Duration | %ss |\n' "$duration"
    printf '\n## Flaky Tests\n\n'
    if [ "$flaky_count" -eq 0 ]; then
      printf 'No flaky tests detected.\n'
    else
      printf '%s test(s) passed in some runs and failed in others:\n\n' "$flaky_count"
      printf '| Test | Passed | Failed |\n'
      printf '| :--- | ---: | ---: |\n'
      local row id p f
      for row in "${flaky_rows[@]}"; do
        IFS=$'\t' read -r id p f <<< "$row"
        # The backticks below are literal Markdown code spans, not a command
        # substitution, hence the SC2016 suppression.
        # shellcheck disable=SC2016
        printf '| `%s` | %s | %s |\n' "$id" "$p" "$f"
      done
    fi
  }

  # ----- Machine-readable counts (optional) -----
  if [ -n "$counts_file" ]; then
    {
      printf 'passed=%s\n'   "$passed"
      printf 'failed=%s\n'   "$failed"
      printf 'skipped=%s\n'  "$skipped"
      printf 'unknown=%s\n'  "$unknown"
      printf 'total=%s\n'    "$total"
      printf 'flaky=%s\n'    "$flaky_count"
      printf 'duration=%s\n' "$duration"
    } > "$counts_file"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local output_file="" counts_file="" title="Test Results Summary"
  local -a paths=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o | --output)      [ "$#" -ge 2 ] || { err "$1 requires an argument"; exit 2; }; output_file="$2"; shift 2 ;;
      -c | --counts-file) [ "$#" -ge 2 ] || { err "$1 requires an argument"; exit 2; }; counts_file="$2"; shift 2 ;;
      -t | --title)       [ "$#" -ge 2 ] || { err "$1 requires an argument"; exit 2; }; title="$2"; shift 2 ;;
      -h | --help)        usage; exit 0 ;;
      --)                 shift; while [ "$#" -gt 0 ]; do paths+=( "$1" ); shift; done ;;
      -*)                 err "unknown option: $1"; usage >&2; exit 2 ;;
      *)                  paths+=( "$1" ); shift ;;
    esac
  done

  if [ "${#paths[@]}" -eq 0 ]; then
    err "no input paths given"
    usage >&2
    exit 2
  fi

  # Expand directories/files into a concrete list of result files.
  local file_list
  if ! file_list="$(collect_files "${paths[@]}")"; then
    exit 1
  fi
  if [ -z "$file_list" ]; then
    err "no test result files (*.xml / *.json) found in: ${paths[*]}"
    exit 1
  fi

  local -a files=()
  mapfile -t files <<< "$file_list"

  # Parse every file into one combined normalised TSV stream.
  local tsv parsed fmt found=0
  tsv="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tsv'" EXIT

  local f
  for f in "${files[@]}"; do
    if ! fmt="$(detect_format "$f")"; then
      err "cannot determine format of: $f (expected JUnit XML or JSON)"
      exit 1
    fi
    case "$fmt" in
      junit) parsed="$(parse_junit_xml "$f")" || { err "failed to parse JUnit XML: $f"; exit 1; } ;;
      json)  parsed="$(parse_json "$f")"      || { err "failed to parse JSON: $f"; exit 1; } ;;
    esac
    if [ -z "$parsed" ]; then
      warn "no test cases found in: $f"
    else
      printf '%s\n' "$parsed" >> "$tsv"
      found=1
    fi
  done

  if [ "$found" -eq 0 ]; then
    err "no test cases were parsed from any input file"
    exit 1
  fi

  # Aggregate and render.
  local summary
  summary="$(aggregate < "$tsv")"

  if [ -n "$output_file" ]; then
    render "$summary" "$title" "$counts_file" > "$output_file"
  else
    render "$summary" "$title" "$counts_file"
  fi
}

main "$@"
