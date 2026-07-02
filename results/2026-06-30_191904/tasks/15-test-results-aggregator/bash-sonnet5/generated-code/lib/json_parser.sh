#!/usr/bin/env bash
# JSON test-result parser -- uses jq (ubiquitous on GitHub Actions
# runners and the project's act image) to do the actual JSON parsing;
# bash just drives it and normalizes the output.
#
# Expected shape:
# {
#   "suite": "name", "run": "label", "duration": 0.81,
#   "tests": [
#     {"name": "...", "classname": "...", "status": "passed|failed|skipped",
#      "duration": 0.11, "message": "optional"}
#   ]
# }

# parse_json_results FILE RUN_ID
#
# Prints one normalized TSV record per test:
#   run_id<TAB>classname<TAB>name<TAB>status<TAB>duration<TAB>message
#
# Exits non-zero with a message on stderr if the file is not valid
# JSON, or does not contain a "tests" array, or a test entry has an
# invalid/missing status or name.
parse_json_results() {
  local file="$1" run_id="$2"

  if [[ ! -f "$file" ]]; then
    echo "ERROR: JSON results file not found: $file" >&2
    return 1
  fi

  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "ERROR: invalid JSON in file '$file'" >&2
    return 1
  fi

  if [[ "$(jq -r 'has("tests")' "$file")" != "true" ]]; then
    echo "ERROR: malformed JSON results file '$file': missing top-level 'tests' array" >&2
    return 1
  fi
  if [[ "$(jq -r '.tests | type' "$file")" != "array" ]]; then
    echo "ERROR: malformed JSON results file '$file': 'tests' must be an array" >&2
    return 1
  fi

  local bad_status
  bad_status=$(jq -r '[.tests[].status] | map(select(. != "passed" and . != "failed" and . != "skipped")) | .[0] // empty' "$file")
  if [[ -n "$bad_status" ]]; then
    echo "ERROR: malformed JSON results file '$file': invalid status '$bad_status' (expected passed, failed, or skipped)" >&2
    return 1
  fi

  local missing_name
  missing_name=$(jq -r '[.tests[] | select((.name // "") == "")] | length' "$file")
  if [[ "$missing_name" != "0" ]]; then
    echo "ERROR: malformed JSON results file '$file': a test entry is missing required 'name' field" >&2
    return 1
  fi

  jq -r --arg run "$run_id" '
    .tests[] |
    [$run, (.classname // ""), .name, .status, ((.duration // 0) | tostring), ((.message // "") | gsub("[\t\n\r]"; " "))]
    | @tsv
  ' "$file"
}
