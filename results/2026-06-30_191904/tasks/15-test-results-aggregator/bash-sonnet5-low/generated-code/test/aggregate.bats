#!/usr/bin/env bats
# TDD: aggregate.sh reads normalized TSV records (file, testname, status, duration)
# on stdin and prints totals + flaky test list. Format chosen to be easy for
# report.sh to consume: lines prefixed with TOTAL_/FLAKY_ tags.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AGGREGATE="$ROOT_DIR/lib/aggregate.sh"
}

@test "aggregate computes passed/failed/skipped/duration totals" {
  run bash -c "printf 'a.xml\tt1\tpassed\t1.0\na.xml\tt2\tfailed\t2.0\na.xml\tt3\tskipped\t0.5\n' | '$AGGREGATE'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^TOTAL_PASSED	1$'
  echo "$output" | grep -qE '^TOTAL_FAILED	1$'
  echo "$output" | grep -qE '^TOTAL_SKIPPED	1$'
  echo "$output" | grep -qE '^TOTAL_DURATION	3.5(0)?$'
}

@test "aggregate identifies a flaky test (passed in one file, failed in another)" {
  run bash -c "printf 'a.xml\tflaky\tpassed\t1.0\nb.xml\tflaky\tfailed\t1.0\n' | '$AGGREGATE'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$(printf 'FLAKY\tflaky')"
}

@test "aggregate does not flag a consistently passing test as flaky" {
  run bash -c "printf 'a.xml\tstable\tpassed\t1.0\nb.xml\tstable\tpassed\t1.0\n' | '$AGGREGATE'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "$(printf 'FLAKY\tstable')"
}

@test "aggregate errors gracefully on empty input" {
  run bash -c "printf '' | '$AGGREGATE'"
  [ "$status" -ne 0 ]
}
