#!/usr/bin/env bash
#
# aggregate.sh - Parse and aggregate test result files (JUnit XML + JSON),
# compute totals (passed / failed / skipped / duration), identify flaky tests
# (tests that both passed and failed across runs), and render a Markdown
# summary suitable for a GitHub Actions job summary.
#
# Design
# ------
# The script is built around a normalized intermediate representation: every
# parser converts its input format into TAB-separated lines of:
#
#     <test name>\t<status>\t<duration seconds>
#
# where <status> is one of: passed | failed | skipped. Aggregation and flaky
# detection then operate purely on this normalized stream, so they are
# format-agnostic and easy to unit test.
#
# Subcommands (kept small so each can be tested in isolation, TDD-style):
#   parse <file>        Auto-detect format and emit normalized TSV.
#   parse-junit <file>  Parse a JUnit XML file -> normalized TSV.
#   parse-json <file>   Parse a JSON file -> normalized TSV.
#   summary <file...>   Parse + aggregate all files -> Markdown summary.
#
set -euo pipefail

# --- Error handling helpers -------------------------------------------------

# die: print a meaningful error message to stderr and exit non-zero.
die() {
	echo "error: $*" >&2
	exit 1
}

# require_file: ensure a path exists and is a readable regular file.
require_file() {
	local f="$1"
	[[ -n "$f" ]] || die "no file specified"
	[[ -e "$f" ]] || die "file not found: $f"
	[[ -f "$f" ]] || die "not a regular file: $f"
	[[ -r "$f" ]] || die "file not readable: $f"
}

# --- JUnit XML parser -------------------------------------------------------
#
# Emits one normalized TSV line per <testcase>. A testcase is:
#   - "skipped" if it contains a <skipped> child
#   - "failed"  if it contains a <failure> or <error> child
#   - "passed"  otherwise
# Self-closing testcases (<testcase .../>) are treated as passed.
# We use awk for line-spanning state tracking so multi-line testcases work.
parse_junit() {
	local file="$1"
	require_file "$file"
	# Basic sanity check: must look like JUnit XML.
	grep -q "<testsuite" "$file" || grep -q "<testcase" "$file" \
		|| die "not a valid JUnit XML file (no <testsuite>/<testcase>): $file"

	awk '
		# Extract the value of attr="..." from the current line. We scan for
		# matches and require the character before the attribute name to be a
		# non-identifier char, so attr("name") does not match classname="...".
		function attr(aname,    re, rest, off, pos, prev) {
			re = aname "=\"[^\"]*\""
			rest = $0
			off = 0
			while (match(rest, re)) {
				pos = off + RSTART
				prev = (pos > 1) ? substr($0, pos - 1, 1) : " "
				if (prev !~ /[a-zA-Z0-9_]/) {
					return substr(rest, RSTART + length(aname) + 2, RLENGTH - length(aname) - 3)
				}
				off += RSTART + RLENGTH - 1
				rest = substr($0, off + 1)
			}
			return ""
		}
		/<testcase/ {
			incase = 1
			name = attr("name")
			time = attr("time")
			if (time == "") time = "0"
			status = "passed"
			# Self-closing tag: complete record on this line.
			if ($0 ~ /\/>/) {
				print name "\t" status "\t" time
				incase = 0
			}
			next
		}
		incase && /<skipped/  { status = "skipped" }
		incase && /<failure/  { if (status != "skipped") status = "failed" }
		incase && /<error/    { if (status != "skipped") status = "failed" }
		incase && /<\/testcase>/ {
			print name "\t" status "\t" time
			incase = 0
		}
	' "$file"
}

# --- JSON parser ------------------------------------------------------------
#
# Expected schema (a deliberately simple, self-describing format):
#   { "tests": [ { "name": "...", "status": "passed|failed|skipped",
#                  "duration": 0.5 }, ... ] }
# Status values are normalized: pass/ok -> passed, fail/error -> failed,
# skip/skipped/ignored -> skipped.
parse_json() {
	local file="$1"
	require_file "$file"
	jq -e . "$file" >/dev/null 2>&1 || die "invalid JSON: $file"
	jq -e 'has("tests") and (.tests | type == "array")' "$file" >/dev/null 2>&1 \
		|| die "JSON missing a \"tests\" array: $file"

	jq -r '
		def norm(s):
			(s // "passed") | ascii_downcase
			| if   . == "pass" or . == "passed" or . == "ok"        then "passed"
			  elif . == "fail" or . == "failed" or . == "error"     then "failed"
			  elif . == "skip" or . == "skipped" or . == "ignored"  then "skipped"
			  else . end;
		.tests[]
		| [ (.name // "unnamed"), norm(.status), ((.duration // 0) | tostring) ]
		| @tsv
	' "$file"
}

# --- Dispatch parser by extension ------------------------------------------
parse_file() {
	local file="$1"
	require_file "$file"
	case "$file" in
		*.xml)        parse_junit "$file" ;;
		*.json)       parse_json  "$file" ;;
		*)
			# Fall back to content sniffing for files without a known extension.
			if head -c 64 "$file" | grep -q "<"; then
				parse_junit "$file"
			else
				parse_json "$file"
			fi
			;;
	esac
}

# --- Aggregation + Markdown summary ----------------------------------------
#
# Reads all given files, normalizes them, then computes totals and flaky tests
# in a single awk pass over the combined stream. Flaky = a test name observed
# with both a "passed" and a "failed" outcome across the runs.
summary() {
	[[ "$#" -gt 0 ]] || die "summary: no input files given"

	local combined
	combined="$(
		for f in "$@"; do
			parse_file "$f"
		done
	)"

	[[ -n "$combined" ]] || die "no test cases found in input files"

	# awk computes everything and prints the Markdown report.
	printf '%s\n' "$combined" | awk -F '\t' '
		{
			name = $1; status = $2; dur = $3 + 0
			total++
			counts[status]++
			duration += dur
			# Track which outcomes each test name has seen (for flaky detect).
			seen_pass[name] += (status == "passed")
			seen_fail[name] += (status == "failed")
		}
		END {
			passed  = counts["passed"]  + 0
			failed  = counts["failed"]  + 0
			skipped = counts["skipped"] + 0

			print "# Test Results Summary"
			print ""
			print "| Metric | Count |"
			print "| --- | --- |"
			printf "| Passed | %d |\n", passed
			printf "| Failed | %d |\n", failed
			printf "| Skipped | %d |\n", skipped
			printf "| Total | %d |\n", total
			printf "| Duration | %.2fs |\n", duration
			print ""

			# Collect flaky test names (sorted for deterministic output).
			n = 0
			for (name in seen_pass) {
				if (seen_pass[name] > 0 && seen_fail[name] > 0) {
					flaky[n++] = name
				}
			}
			# Simple insertion sort to keep output deterministic without
			# relying on awk array traversal order.
			for (i = 1; i < n; i++) {
				key = flaky[i]; j = i - 1
				while (j >= 0 && flaky[j] > key) { flaky[j+1] = flaky[j]; j-- }
				flaky[j+1] = key
			}

			print "## Flaky Tests"
			print ""
			if (n == 0) {
				print "None detected."
			} else {
				printf "Detected %d flaky test(s) (passed in some runs, failed in others):\n", n
				print ""
				for (i = 0; i < n; i++) {
					print "- " flaky[i]
				}
			}

			# Overall status line, useful for CI consumers.
			print ""
			if (failed > 0) {
				print "**Result: FAILED**"
			} else {
				print "**Result: PASSED**"
			}
		}
	'
}

# --- Machine-readable totals -----------------------------------------------
#
# Emits KEY=VALUE lines (passed/failed/skipped/total/duration/flaky), which is
# directly consumable by $GITHUB_OUTPUT in the workflow. `flaky` is a
# comma-separated, sorted list (empty if none).
totals() {
	[[ "$#" -gt 0 ]] || die "totals: no input files given"

	local combined
	combined="$(
		for f in "$@"; do
			parse_file "$f"
		done
	)"
	[[ -n "$combined" ]] || die "no test cases found in input files"

	printf '%s\n' "$combined" | awk -F '\t' '
		{
			name = $1; status = $2
			total++
			counts[status]++
			duration += ($3 + 0)
			seen_pass[name] += (status == "passed")
			seen_fail[name] += (status == "failed")
		}
		END {
			n = 0
			for (name in seen_pass)
				if (seen_pass[name] > 0 && seen_fail[name] > 0) flaky[n++] = name
			for (i = 1; i < n; i++) {
				key = flaky[i]; j = i - 1
				while (j >= 0 && flaky[j] > key) { flaky[j+1] = flaky[j]; j-- }
				flaky[j+1] = key
			}
			list = ""
			for (i = 0; i < n; i++) list = list (i ? "," : "") flaky[i]

			printf "passed=%d\n",  counts["passed"]  + 0
			printf "failed=%d\n",  counts["failed"]  + 0
			printf "skipped=%d\n", counts["skipped"] + 0
			printf "total=%d\n",   total
			printf "duration=%.2f\n", duration
			printf "flaky=%s\n",   list
		}
	'
}

# --- Entry point ------------------------------------------------------------
main() {
	local cmd="${1:-}"
	[[ -n "$cmd" ]] || die "usage: $0 <parse|parse-junit|parse-json|summary> <file...>"
	shift

	case "$cmd" in
		parse)        parse_file "$@" ;;
		parse-junit)  parse_junit "$@" ;;
		parse-json)   parse_json  "$@" ;;
		summary)      summary     "$@" ;;
		totals)       totals      "$@" ;;
		*)            die "unknown command: $cmd (expected parse|parse-junit|parse-json|summary|totals)" ;;
	esac
}

main "$@"
