#!/usr/bin/env bash
# Aggregation engine -- pure bash associative arrays, no awk/bc/python.
#
# Durations are tracked as integer centiseconds (hundredths of a second)
# so totals can be summed with bash's native integer arithmetic instead
# of relying on an external tool for floating point math.

declare -a AGG_RUN_IDS=()
declare -A AGG_SEEN_RUNS=()
declare -a AGG_TEST_KEYS=()
declare -A AGG_SEEN_TESTS=()

declare -A AGG_RUN_PASSED=()
declare -A AGG_RUN_FAILED=()
declare -A AGG_RUN_SKIPPED=()
declare -A AGG_RUN_CENTIS=()

declare -A AGG_TEST_PASS=()
declare -A AGG_TEST_FAIL=()
declare -A AGG_TEST_SKIP=()
declare -A AGG_TEST_LAST_FAIL_MSG=()
declare -A AGG_TEST_STATUS_BY_RUN=()

AGG_TOTAL_PASSED=0
AGG_TOTAL_FAILED=0
AGG_TOTAL_SKIPPED=0
AGG_TOTAL_CENTIS=0

# Reset all aggregation state. Useful if a script sources this library
# and wants to run multiple independent aggregations in one process.
aggregator_reset() {
  AGG_RUN_IDS=()
  AGG_SEEN_RUNS=()
  AGG_TEST_KEYS=()
  AGG_SEEN_TESTS=()
  AGG_RUN_PASSED=()
  AGG_RUN_FAILED=()
  AGG_RUN_SKIPPED=()
  AGG_RUN_CENTIS=()
  AGG_TEST_PASS=()
  AGG_TEST_FAIL=()
  AGG_TEST_SKIP=()
  AGG_TEST_LAST_FAIL_MSG=()
  AGG_TEST_STATUS_BY_RUN=()
  AGG_TOTAL_PASSED=0
  AGG_TOTAL_FAILED=0
  AGG_TOTAL_SKIPPED=0
  AGG_TOTAL_CENTIS=0
}

# Convert a decimal seconds string (e.g. "1.5", "0.10", "3") to integer
# centiseconds. Truncates (does not round) beyond 2 decimal places.
aggregator_to_centis() {
  local v="$1"
  [[ -z "$v" ]] && v="0"
  [[ $v != *.* ]] && v="${v}.00"
  local int="${v%%.*}" frac="${v#*.}"
  [[ -z "$int" ]] && int="0"
  frac="${frac}00"
  frac="${frac:0:2}"
  printf '%d' "$((10#$int * 100 + 10#$frac))"
}

# Format integer centiseconds back into an "X.XXs" string.
aggregator_centis_to_str() {
  local centis="$1"
  printf '%d.%02ds' "$((centis / 100))" "$((centis % 100))"
}

# aggregator_add_record RUN CLASSNAME NAME STATUS DURATION MESSAGE
aggregator_add_record() {
  local run="$1" classname="$2" name="$3" status="$4" duration="$5" message="$6"
  local key="${classname}::${name}"
  local centis
  centis=$(aggregator_to_centis "$duration")

  if [[ -z "${AGG_SEEN_RUNS[$run]:-}" ]]; then
    AGG_SEEN_RUNS[$run]=1
    AGG_RUN_IDS+=("$run")
  fi
  if [[ -z "${AGG_SEEN_TESTS[$key]:-}" ]]; then
    AGG_SEEN_TESTS[$key]=1
    AGG_TEST_KEYS+=("$key")
  fi

  AGG_RUN_CENTIS[$run]=$(( ${AGG_RUN_CENTIS[$run]:-0} + centis ))
  AGG_TOTAL_CENTIS=$(( AGG_TOTAL_CENTIS + centis ))
  AGG_TEST_STATUS_BY_RUN["${key}|${run}"]="$status"

  case "$status" in
    passed)
      AGG_RUN_PASSED[$run]=$(( ${AGG_RUN_PASSED[$run]:-0} + 1 ))
      AGG_TEST_PASS[$key]=$(( ${AGG_TEST_PASS[$key]:-0} + 1 ))
      AGG_TOTAL_PASSED=$(( AGG_TOTAL_PASSED + 1 ))
      ;;
    failed)
      AGG_RUN_FAILED[$run]=$(( ${AGG_RUN_FAILED[$run]:-0} + 1 ))
      AGG_TEST_FAIL[$key]=$(( ${AGG_TEST_FAIL[$key]:-0} + 1 ))
      AGG_TOTAL_FAILED=$(( AGG_TOTAL_FAILED + 1 ))
      [[ -n "$message" ]] && AGG_TEST_LAST_FAIL_MSG[$key]="$message"
      ;;
    skipped)
      AGG_RUN_SKIPPED[$run]=$(( ${AGG_RUN_SKIPPED[$run]:-0} + 1 ))
      AGG_TEST_SKIP[$key]=$(( ${AGG_TEST_SKIP[$key]:-0} + 1 ))
      AGG_TOTAL_SKIPPED=$(( AGG_TOTAL_SKIPPED + 1 ))
      ;;
    *)
      echo "ERROR: unknown test status '$status' for '$key' in run '$run'" >&2
      return 1
      ;;
  esac
  return 0
}

# Ingest normalized TSV records (run\tclassname\tname\tstatus\tduration\tmessage)
# from stdin.
aggregator_ingest_tsv() {
  local run classname name status duration message
  while IFS=$'\t' read -r run classname name status duration message; do
    [[ -z "$run" && -z "$name" ]] && continue
    aggregator_add_record "$run" "$classname" "$name" "$status" "$duration" "$message" || return 1
  done
  return 0
}

# True (0) if test $1 (classname::name) is flaky: passed at least once
# AND failed at least once across the ingested runs.
aggregator_is_flaky() {
  local key="$1"
  (( ${AGG_TEST_PASS[$key]:-0} > 0 && ${AGG_TEST_FAIL[$key]:-0} > 0 ))
}

# True (0) if test $1 failed in every run it appeared in and never passed.
aggregator_is_consistently_failing() {
  local key="$1"
  (( ${AGG_TEST_FAIL[$key]:-0} > 0 && ${AGG_TEST_PASS[$key]:-0} == 0 ))
}

# Print the most recent failure message recorded for test $1, if any.
aggregator_last_fail_message() {
  local key="$1"
  printf '%s' "${AGG_TEST_LAST_FAIL_MSG[$key]:-}"
}

# Print "run1=status, run2=status, ..." for test $1 across all known runs,
# in run-encounter order. Runs where the test did not appear are omitted.
aggregator_test_pattern() {
  local key="$1" run status result=""
  for run in "${AGG_RUN_IDS[@]}"; do
    status="${AGG_TEST_STATUS_BY_RUN["${key}|${run}"]:-}"
    [[ -z "$status" ]] && continue
    if [[ -z "$result" ]]; then
      result="${run}=${status}"
    else
      result="${result}, ${run}=${status}"
    fi
  done
  printf '%s' "$result"
}
