#!/usr/bin/env bash
#
# aggregate.sh — Parse and aggregate test result files (JUnit XML + JSON).
#
# Reads one or more test result files (or directories containing them),
# normalizes every test case into a common tab-separated record, aggregates
# totals across all files (simulating a CI matrix build), detects flaky tests
# (those that both passed and failed across runs), and emits a Markdown summary
# suitable for a GitHub Actions job summary ($GITHUB_STEP_SUMMARY).
#
# Normalized record (one test case per line), tab-separated:
#     status <TAB> duration <TAB> classname <TAB> name <TAB> file
# where status is one of: passed | failed | skipped.

set -euo pipefail

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: aggregate.sh [options] <file-or-dir>...

Parse JUnit XML and JSON test result files, aggregate results across files,
detect flaky tests, and print a Markdown summary to stdout.

Arguments:
  <file-or-dir>...      One or more result files or directories to scan
                        (directories are searched for *.xml and *.json).

Options:
  -o, --output FILE     Write the Markdown summary to FILE (default: stdout).
  --fail-on-failure     Exit non-zero if any test failed (default: exit 0).
  -h, --help            Show this help and exit.

Supported formats:
  JUnit XML  - <testsuite>/<testsuites> with <testcase> elements; a child
               <failure>/<error> marks a failure, <skipped> marks a skip.
  JSON       - { "tests": [ { "name", "classname", "status", "duration" } ] }
               status is one of: passed | failed | skipped.
EOF
}

# Print an error message to stderr, prefixed with the program name.
err() {
    echo "aggregate.sh: error: $*" >&2
}

# ---------------------------------------------------------------------------
# Format detection — by extension first, falling back to content sniffing.
# ---------------------------------------------------------------------------
detect_format() {
    local file="$1"
    case "$file" in
        *.xml|*.XML) echo junit ; return 0 ;;
        *.json|*.JSON) echo json ; return 0 ;;
    esac
    # Sniff the first non-whitespace character for files with other names.
    local c
    c=$(tr -d '[:space:]' < "$file" | head -c 1)
    case "$c" in
        '<') echo junit ;;
        '{'|'[') echo json ;;
        *) echo unknown ;;
    esac
}

# ---------------------------------------------------------------------------
# JUnit XML parser
#
# Strategy (dependency-free, no xmllint): flatten the document to one stream,
# then start every <testcase> on its own line so each line contains exactly one
# test case together with its children (<failure>/<error>/<skipped>) up to the
# next <testcase>. An awk pass then classifies each case and extracts its
# name/classname/time attributes. Attribute lookups require a leading space so
# that "classname" can never be mistaken for "name".
# ---------------------------------------------------------------------------
parse_junit_xml() {
    local file="$1"
    tr '\n' ' ' < "$file" \
        | sed -e 's/<testcase/\n<testcase/g' \
        | grep '<testcase' \
        | awk -v file="$file" '
            function attr(s, key,   re) {
                re = " " key "=\""
                if (match(s, re)) {
                    s = substr(s, RSTART + length(re))
                    sub(/".*/, "", s)
                    return s
                }
                return ""
            }
            {
                line = $0
                # Isolate the opening tag: everything up to the first ">".
                open = line
                sub(/>.*/, ">", open)

                name = attr(open, "name")
                classname = attr(open, "classname")
                time = attr(open, "time")
                if (time == "") time = "0"

                if (line ~ /<failure|<error/)   status = "failed"
                else if (line ~ /<skipped/)     status = "skipped"
                else                            status = "passed"

                printf "%s\t%s\t%s\t%s\t%s\n", status, time, classname, name, file
            }
        '
}

# ---------------------------------------------------------------------------
# JSON parser (uses jq). Missing fields default sensibly so partial fixtures
# still parse: status -> passed, duration -> 0, classname -> "".
# ---------------------------------------------------------------------------
parse_json() {
    local file="$1"
    if ! jq -e 'has("tests") and (.tests | type == "array")' "$file" >/dev/null 2>&1; then
        err "JSON file '$file' has no top-level \"tests\" array"
        return 1
    fi
    jq -r --arg file "$file" '
        .tests[]
        | [ (.status // "passed"),
            ((.duration // 0) | tostring),
            (.classname // ""),
            (.name // "<unnamed>"),
            $file ]
        | @tsv
    ' "$file"
}

# ---------------------------------------------------------------------------
# Collect input files: expand directories to the *.xml/*.json they contain,
# keep regular files as-is, and fail on anything that does not exist.
# Emits one path per line (sorted for deterministic output).
# ---------------------------------------------------------------------------
collect_files() {
    local arg
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            find "$arg" -type f \( -name '*.xml' -o -name '*.json' \) | sort
        elif [ -f "$arg" ]; then
            echo "$arg"
        else
            err "no such file or directory: '$arg'"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Aggregation: read normalized TSV records on stdin and emit structured lines:
#   TOTALS <total> <passed> <failed> <skipped> <duration>
#   FLAKY  <classname::name> <passes> <fails>          (one per flaky test)
#   FILE   <file> <total> <passed> <failed> <skipped> <duration> (per file)
# A test is flaky when the same classname::name key was observed both passed
# and failed across the aggregated files.
# ---------------------------------------------------------------------------
aggregate_records() {
    awk -F'\t' '
        {
            file = $5
            total++
            files[file] = 1
            ftotal[file]++
            d = $2 + 0
            sumdur += d
            fdur[file] += d
            key = $3 "::" $4
            if ($1 == "passed")  { passed++;  fpass[file]++; p[key]++ }
            else if ($1 == "failed")  { failed++;  ffail[file]++; f[key]++ }
            else if ($1 == "skipped") { skipped++; fskip[file]++ }
        }
        END {
            printf "TOTALS\t%d\t%d\t%d\t%d\t%.2f\n", \
                total, passed + 0, failed + 0, skipped + 0, sumdur
            for (k in p)
                if (k in f)
                    printf "FLAKY\t%s\t%d\t%d\n", k, p[k], f[k]
            for (fl in files)
                printf "FILE\t%s\t%d\t%d\t%d\t%d\t%.2f\n", \
                    fl, ftotal[fl], fpass[fl] + 0, ffail[fl] + 0, fskip[fl] + 0, fdur[fl]
        }
    '
}

# ---------------------------------------------------------------------------
# Markdown rendering. Reads the structured aggregation lines from a temp file
# and writes a GitHub-flavored Markdown summary to stdout.
# ---------------------------------------------------------------------------
render_markdown() {
    local agg_file="$1" nfiles="$2"

    local totals_line total passed failed skipped duration
    totals_line=$(grep '^TOTALS' "$agg_file" || true)
    IFS=$'\t' read -r _ total passed failed skipped duration <<<"$totals_line"
    : "${total:=0}" "${passed:=0}" "${failed:=0}" "${skipped:=0}" "${duration:=0.00}"

    local flaky_count
    flaky_count=$(grep -c '^FLAKY' "$agg_file" || true)

    echo "# Test Results Summary"
    echo
    echo "Aggregated **${nfiles}** result file(s) (matrix build)."
    echo
    echo "| Metric | Value |"
    echo "| :--- | ---: |"
    echo "| Total | ${total} |"
    echo "| Passed | ${passed} |"
    echo "| Failed | ${failed} |"
    echo "| Skipped | ${skipped} |"
    echo "| Flaky | ${flaky_count} |"
    echo "| Duration | ${duration}s |"
    echo

    # Per-file breakdown, sorted by file path for deterministic output.
    echo "## Per-file Breakdown"
    echo
    echo "| File | Total | Passed | Failed | Skipped | Duration |"
    echo "| :--- | ---: | ---: | ---: | ---: | ---: |"
    grep '^FILE' "$agg_file" | sort -t$'\t' -k2 | while IFS=$'\t' read -r _ fl ft fp ff fs fd; do
        echo "| $(basename "$fl") | ${ft} | ${fp} | ${ff} | ${fs} | ${fd}s |"
    done
    echo

    # Flaky tests section.
    echo "## Flaky Tests"
    echo
    if [ "${flaky_count}" -eq 0 ]; then
        echo "None detected. No test both passed and failed across runs."
    else
        echo "These tests both passed and failed across runs:"
        echo
        echo "| Test | Passes | Fails |"
        echo "| :--- | ---: | ---: |"
        grep '^FLAKY' "$agg_file" | sort -t$'\t' -k2 | while IFS=$'\t' read -r _ key np nf; do
            echo "| ${key} | ${np} | ${nf} |"
        done
    fi
    echo

    # Overall verdict line.
    echo "## Result"
    echo
    if [ "${failed}" -gt 0 ]; then
        echo "**FAILED** — ${failed} test(s) failed across ${nfiles} file(s)."
    else
        echo "**PASSED** — all ${total} test(s) passed across ${nfiles} file(s)."
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    local output="" fail_on_failure=0
    local -a inputs=()

    # Parse options and positional arguments.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            -o|--output)
                if [ "$#" -lt 2 ]; then err "--output requires a FILE argument"; return 1; fi
                output="$2"; shift 2 ;;
            --output=*) output="${1#*=}"; shift ;;
            --fail-on-failure) fail_on_failure=1; shift ;;
            --) shift; while [ "$#" -gt 0 ]; do inputs+=("$1"); shift; done ;;
            -*) err "unknown option: '$1'"; usage >&2; return 1 ;;
            *) inputs+=("$1"); shift ;;
        esac
    done

    if [ "${#inputs[@]}" -eq 0 ]; then
        echo "Usage: aggregate.sh [options] <file-or-dir>..." >&2
        err "no input files or directories given"
        return 1
    fi

    # Expand directories and validate paths.
    local files_list
    if ! files_list=$(collect_files "${inputs[@]}"); then
        return 1
    fi
    if [ -z "$files_list" ]; then
        err "no test result files (*.xml/*.json) found in the given inputs"
        return 1
    fi

    # Parse every file into the shared normalized-record temp file.
    local records_file agg_file
    records_file=$(mktemp)
    agg_file=$(mktemp)
    # shellcheck disable=SC2064  # expand paths now so cleanup is robust.
    trap "rm -f '$records_file' '$agg_file'" EXIT

    local nfiles=0 file fmt
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        fmt=$(detect_format "$file")
        case "$fmt" in
            junit) parse_junit_xml "$file" >>"$records_file" ;;
            json)  parse_json "$file" >>"$records_file" ;;
            *)     err "unrecognized format for file: '$file'"; return 1 ;;
        esac
        nfiles=$((nfiles + 1))
    done <<<"$files_list"

    # Aggregate and render.
    aggregate_records <"$records_file" >"$agg_file"

    local markdown
    markdown=$(render_markdown "$agg_file" "$nfiles")

    if [ -n "$output" ]; then
        printf '%s\n' "$markdown" >"$output"
    else
        printf '%s\n' "$markdown"
    fi

    # Emit a compact, machine-readable line on stderr for CI logs/harnesses.
    local t p f s d fl
    IFS=$'\t' read -r _ t p f s d < <(grep '^TOTALS' "$agg_file")
    fl=$(grep -c '^FLAKY' "$agg_file" || true)
    echo "aggregate.sh: total=${t} passed=${p} failed=${f} skipped=${s} flaky=${fl} duration=${d}s files=${nfiles}" >&2

    # Optionally fail the run when any test failed.
    if [ "$fail_on_failure" -eq 1 ] && [ "${f:-0}" -gt 0 ]; then
        return 1
    fi
    return 0
}

main "$@"
