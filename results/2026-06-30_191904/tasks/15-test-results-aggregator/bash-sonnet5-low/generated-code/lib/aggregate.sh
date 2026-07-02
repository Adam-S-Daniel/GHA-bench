#!/usr/bin/env bash
# Reads normalized TSV records (file, testname, status, duration) on stdin and
# prints machine-readable summary lines consumed by report.sh:
#   TOTAL_PASSED\t<n>   TOTAL_FAILED\t<n>   TOTAL_SKIPPED\t<n>   TOTAL_DURATION\t<n>
#   FLAKY\t<testname>   (one line per flaky test, sorted, deduped)
#
# Flaky definition: a test name that appears with status=passed in at least one
# input record AND status=failed in at least one (possibly different) input
# record. We key purely on test name (not file), since the same test run across
# matrix jobs is what we want to catch as inconsistent/flaky.

set -euo pipefail

die() {
  echo "aggregate: $*" >&2
  exit 1
}

main() {
  local input
  input="$(cat)"
  [ -n "$input" ] || die "no input records given (empty stdin)"

  awk -F'\t' '
    {
      status_count[$3]++
      duration_total += $4
      test_status[$2, $3] = 1
      if (!($2 in seen_tests)) { seen_tests[$2]=1; test_order[++n]=$2 }
    }
    END {
      printf "TOTAL_PASSED\t%d\n", status_count["passed"]+0
      printf "TOTAL_FAILED\t%d\n", status_count["failed"]+0
      printf "TOTAL_SKIPPED\t%d\n", status_count["skipped"]+0
      printf "TOTAL_DURATION\t%.2f\n", duration_total+0
      for (i=1; i<=n; i++) {
        t=test_order[i]
        if ((t,"passed") in test_status && (t,"failed") in test_status) {
          print "FLAKY\t" t
        }
      }
    }
  ' <<< "$input"
}

main "$@"
