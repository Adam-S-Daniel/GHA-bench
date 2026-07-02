#!/usr/bin/env bash
# Run every fixture case in fixtures/cases/ through the matrix generator CLI
# and print one delimited, machine-parseable result line per case.
#
# Naming convention encodes the expectation:
#   ok-*.json   -> CLI must exit 0 (line: CASE_OUTPUT <name> EXIT=0 <json>)
#   fail-*.json -> CLI must exit non-zero (line carries the error message)
# The step fails if any case violates its expectation, so the CI job itself
# asserts the generator's behavior.
set -uo pipefail

status=0
shopt -s nullglob
cases=(fixtures/cases/*.json)
if [ ${#cases[@]} -eq 0 ]; then
  echo "No fixture cases found in fixtures/cases/" >&2
  exit 1
fi

for fixture in "${cases[@]}"; do
  name=$(basename "$fixture" .json)
  echo "::CASE::${name}::BEGIN"
  if output=$(bun run src/cli.ts "$fixture" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi
  echo "CASE_OUTPUT ${name} EXIT=${exit_code} ${output}"
  case "$name" in
    ok-*)
      if [ "$exit_code" -ne 0 ]; then
        echo "CASE_VIOLATION ${name}: expected success, got exit ${exit_code}" >&2
        status=1
      fi
      ;;
    fail-*)
      if [ "$exit_code" -eq 0 ]; then
        echo "CASE_VIOLATION ${name}: expected failure, but CLI succeeded" >&2
        status=1
      fi
      ;;
    *)
      echo "CASE_VIOLATION ${name}: case files must be named ok-*.json or fail-*.json" >&2
      status=1
      ;;
  esac
  echo "::CASE::${name}::END"
done

exit "$status"
