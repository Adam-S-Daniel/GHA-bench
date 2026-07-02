#!/usr/bin/env bash
# Markdown renderer -- turns the aggregator's state (lib/aggregator.sh)
# into a GitHub Actions job-summary-friendly markdown document.
#
# Requires lib/aggregator.sh to already be sourced and populated
# (via aggregator_ingest_tsv) before render_markdown_summary is called.

# Escape '|' so a value can't break out of a markdown table cell.
_render_escape_cell() {
  printf '%s' "${1//|/\\|}"
}

render_markdown_summary() {
  local total_tests=$((AGG_TOTAL_PASSED + AGG_TOTAL_FAILED + AGG_TOTAL_SKIPPED))

  echo "# Test Results Summary"
  echo
  echo "## Overall Totals"
  echo
  echo "| Metric | Value |"
  echo "| --- | --- |"
  echo "| Total Tests | ${total_tests} |"
  echo "| Passed | ${AGG_TOTAL_PASSED} |"
  echo "| Failed | ${AGG_TOTAL_FAILED} |"
  echo "| Skipped | ${AGG_TOTAL_SKIPPED} |"
  echo "| Duration | $(aggregator_centis_to_str "$AGG_TOTAL_CENTIS") |"
  echo

  echo "## Per-Run Breakdown"
  echo
  if ((${#AGG_RUN_IDS[@]} == 0)); then
    echo "No test records found."
  else
    echo "| Run | Passed | Failed | Skipped | Duration |"
    echo "| --- | --- | --- | --- | --- |"
    local run
    for run in "${AGG_RUN_IDS[@]}"; do
      printf '| %s | %d | %d | %d | %s |\n' \
        "$(_render_escape_cell "$run")" \
        "${AGG_RUN_PASSED[$run]:-0}" \
        "${AGG_RUN_FAILED[$run]:-0}" \
        "${AGG_RUN_SKIPPED[$run]:-0}" \
        "$(aggregator_centis_to_str "${AGG_RUN_CENTIS[$run]:-0}")"
    done
  fi
  echo

  local -a flaky=()
  local -a failing=()
  local key
  for key in "${AGG_TEST_KEYS[@]}"; do
    aggregator_is_flaky "$key" && flaky+=("$key")
    aggregator_is_consistently_failing "$key" && failing+=("$key")
  done

  echo "## Flaky Tests (${#flaky[@]})"
  echo
  if ((${#flaky[@]} == 0)); then
    echo "No flaky tests detected."
  else
    echo "| Test | Pass | Fail | Detail |"
    echo "| --- | --- | --- | --- |"
    for key in "${flaky[@]}"; do
      printf '| %s | %d | %d | %s |\n' \
        "$(_render_escape_cell "$key")" \
        "${AGG_TEST_PASS[$key]:-0}" \
        "${AGG_TEST_FAIL[$key]:-0}" \
        "$(_render_escape_cell "$(aggregator_test_pattern "$key")")"
    done
  fi
  echo

  echo "## Consistently Failing Tests (${#failing[@]})"
  echo
  if ((${#failing[@]} == 0)); then
    echo "No consistently failing tests detected."
  else
    echo "| Test | Failures | Message |"
    echo "| --- | --- | --- |"
    for key in "${failing[@]}"; do
      local total_runs=$(( ${AGG_TEST_FAIL[$key]:-0} + ${AGG_TEST_PASS[$key]:-0} + ${AGG_TEST_SKIP[$key]:-0} ))
      printf '| %s | %d/%d | %s |\n' \
        "$(_render_escape_cell "$key")" \
        "${AGG_TEST_FAIL[$key]:-0}" \
        "$total_runs" \
        "$(_render_escape_cell "$(aggregator_last_fail_message "$key")")"
    done
  fi
}
