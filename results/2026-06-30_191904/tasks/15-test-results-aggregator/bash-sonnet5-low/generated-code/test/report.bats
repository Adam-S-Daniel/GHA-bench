#!/usr/bin/env bats
# TDD: report.sh consumes aggregate.sh's TOTAL_*/FLAKY tagged lines on stdin and
# renders a GitHub-Actions-friendly Markdown summary.

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REPORT="$ROOT_DIR/lib/report.sh"
}

@test "report renders a totals table with passed/failed/skipped/duration" {
  run bash -c "printf 'TOTAL_PASSED\t5\nTOTAL_FAILED\t2\nTOTAL_SKIPPED\t1\nTOTAL_DURATION\t3.50\n' | '$REPORT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Test Results Summary"* ]]
  [[ "$output" == *"| Passed | 5 |"* ]]
  [[ "$output" == *"| Failed | 2 |"* ]]
  [[ "$output" == *"| Skipped | 1 |"* ]]
  [[ "$output" == *"| Duration (s) | 3.50 |"* ]]
}

@test "report includes a flaky-tests section listing each flaky test" {
  run bash -c "printf 'TOTAL_PASSED\t1\nTOTAL_FAILED\t1\nTOTAL_SKIPPED\t0\nTOTAL_DURATION\t1.00\nFLAKY\ttest_network_timeout\n' | '$REPORT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Flaky Tests"* ]]
  [[ "$output" == *"test_network_timeout"* ]]
}

@test "report notes when there are no flaky tests" {
  run bash -c "printf 'TOTAL_PASSED\t1\nTOTAL_FAILED\t0\nTOTAL_SKIPPED\t0\nTOTAL_DURATION\t1.00\n' | '$REPORT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No flaky tests detected"* ]]
}
