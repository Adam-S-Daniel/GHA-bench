#!/usr/bin/env bash
# Renders aggregate.sh's TOTAL_*/FLAKY tagged TSV lines (stdin) as Markdown
# suitable for $GITHUB_STEP_SUMMARY: a totals table plus a flaky-tests section.

set -euo pipefail

main() {
  local passed=0 failed=0 skipped=0 duration=0
  local -a flaky=()

  while IFS=$'\t' read -r key value; do
    case "$key" in
      TOTAL_PASSED) passed="$value" ;;
      TOTAL_FAILED) failed="$value" ;;
      TOTAL_SKIPPED) skipped="$value" ;;
      TOTAL_DURATION) duration="$value" ;;
      FLAKY) flaky+=("$value") ;;
    esac
  done

  echo "# Test Results Summary"
  echo
  echo "| Metric | Value |"
  echo "| --- | --- |"
  echo "| Passed | $passed |"
  echo "| Failed | $failed |"
  echo "| Skipped | $skipped |"
  echo "| Duration (s) | $duration |"
  echo
  echo "## Flaky Tests"
  echo
  if [ "${#flaky[@]}" -eq 0 ]; then
    echo "No flaky tests detected."
  else
    for t in "${flaky[@]}"; do
      echo "- \`$t\`"
    done
  fi
}

main "$@"
