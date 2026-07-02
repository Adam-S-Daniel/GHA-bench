#!/usr/bin/env bash
# test-results-aggregator.sh
#
# Parses JUnit XML and JSON test-result files, aggregates results across
# multiple files (simulating legs of a CI matrix build), computes totals
# (passed/failed/skipped/duration), flags flaky tests (tests that passed in
# some files and failed in others), and renders a GitHub Actions-friendly
# markdown summary on stdout.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: test-results-aggregator.sh <file1> [file2 ...]

Accepts JUnit XML (.xml) and JSON (.json) test result files, one per
matrix leg. Prints a markdown summary of aggregated totals and any
flaky tests (pass in one leg, fail in another) to stdout.
EOF
    exit 1
}

# Parse a JUnit XML file into TSV rows: name<TAB>status<TAB>duration
parse_junit() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET

filepath = sys.argv[1]
try:
    root = ET.parse(filepath).getroot()
except ET.ParseError as e:
    print(f"ERROR: cannot parse XML '{filepath}': {e}", file=sys.stderr)
    sys.exit(1)

# Support both a <testsuites> wrapper and a bare <testsuite> root.
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))

for suite in suites:
    for tc in suite.findall("testcase"):
        classname = tc.get("classname", "")
        name = tc.get("name", "")
        full_name = f"{classname}.{name}" if classname else name
        duration = tc.get("time") or "0"

        if tc.find("failure") is not None or tc.find("error") is not None:
            status = "failed"
        elif tc.find("skipped") is not None:
            status = "skipped"
        else:
            status = "passed"

        print(f"{full_name}\t{status}\t{duration}")
PYEOF
}

# Parse a JSON results file into TSV rows: name<TAB>status<TAB>duration
parse_json() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import json
import sys

filepath = sys.argv[1]
try:
    with open(filepath) as f:
        data = json.load(f)
except (json.JSONDecodeError, OSError) as e:
    print(f"ERROR: cannot parse JSON '{filepath}': {e}", file=sys.stderr)
    sys.exit(1)

for t in data.get("tests", []):
    name = str(t.get("name", "unknown"))
    status = str(t.get("status", "unknown")).lower()
    duration = str(t.get("duration", 0))
    print(f"{name}\t{status}\t{duration}")
PYEOF
}

# Given a TSV file of name<TAB>status rows, print the names of tests that
# appear with both a "passed" and a "failed" status (i.e. flaky).
detect_flaky() {
    local results_file="$1"
    python3 - "$results_file" <<'PYEOF'
import sys
from collections import defaultdict

statuses = defaultdict(set)
with open(sys.argv[1]) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2 and parts[0]:
            statuses[parts[0]].add(parts[1])

for name in sorted(statuses):
    if "passed" in statuses[name] and "failed" in statuses[name]:
        print(name)
PYEOF
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    # Validate every input up front so we fail fast before doing any work.
    for f in "$@"; do
        if [[ ! -f "$f" ]]; then
            echo "ERROR: file not found: '$f'" >&2
            exit 1
        fi
        case "${f##*.}" in
            xml|json) ;;
            *)
                echo "ERROR: Unsupported file extension for '$f' (expected .xml or .json)" >&2
                exit 1
                ;;
        esac
    done

    local tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT

    local results_file="$tmpdir/results.tsv"
    : > "$results_file"

    local total_passed=0 total_failed=0 total_skipped=0 total_duration="0" file_count=0

    for file in "$@"; do
        file_count=$((file_count + 1))
        local ext="${file##*.}"
        local parsed
        if [[ "$ext" == "xml" ]]; then
            parsed="$(parse_junit "$file")"
        else
            parsed="$(parse_json "$file")"
        fi

        while IFS=$'\t' read -r name status duration; do
            [[ -z "$name" ]] && continue
            printf '%s\t%s\n' "$name" "$status" >> "$results_file"

            case "$status" in
                passed)  total_passed=$((total_passed + 1)) ;;
                failed)  total_failed=$((total_failed + 1)) ;;
                skipped) total_skipped=$((total_skipped + 1)) ;;
            esac

            total_duration="$(awk -v a="$total_duration" -v b="$duration" 'BEGIN { printf "%.2f", a + b }')"
        done <<< "$parsed"
    done

    local total_tests=$((total_passed + total_failed + total_skipped))

    local flaky_output=""
    if [[ -s "$results_file" ]]; then
        flaky_output="$(detect_flaky "$results_file")"
    fi
    local flaky_count=0
    if [[ -n "$flaky_output" ]]; then
        flaky_count="$(grep -c '[^[:space:]]' <<< "$flaky_output")"
    fi

    local status_badge="PASSED"
    [[ "$total_failed" -gt 0 ]] && status_badge="FAILED"

    cat <<EOF
# Test Results Summary

**Status: ${status_badge}**

## Overview

| Metric | Value |
|--------|-------|
| Files Processed | ${file_count} |
| Total Tests | ${total_tests} |
| Passed | ${total_passed} |
| Failed | ${total_failed} |
| Skipped | ${total_skipped} |
| Duration | ${total_duration}s |

## Flaky Tests
EOF

    if [[ "$flaky_count" -eq 0 ]]; then
        printf '\nNo flaky tests detected.\n'
    else
        printf '\nThe following tests were inconsistent across matrix runs (passed in some, failed in others):\n\n'
        printf '| Test Name | Issue |\n|-----------|-------|\n'
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            echo "| \`${name}\` | Passed in some runs, failed in others |"
        done <<< "$flaky_output"
    fi

    printf '\n## Files Analyzed\n\n'
    for f in "$@"; do
        echo "- \`${f}\`"
    done
}

main "$@"
