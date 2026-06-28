// Markdown rendering for a GitHub Actions job summary.
//
// The output is plain GitHub-flavored markdown so it can be written straight to
// $GITHUB_STEP_SUMMARY and render as a rich job summary in the Actions UI.

import type { Aggregation } from "./types.ts";

/** Format a duration (seconds) as e.g. "12.50s". */
function fmtDuration(seconds: number): string {
  return `${seconds.toFixed(2)}s`;
}

/**
 * Render the full markdown summary for an aggregation result.
 *
 * Sections:
 *   1. Overall status badge (PASS/FAIL) + file count.
 *   2. Totals table (passed/failed/skipped/total/duration).
 *   3. Flaky tests table, or a "clean bill" line when none were found.
 */
export function renderSummary(agg: Aggregation): string {
  const { totals, flaky, fileCount } = agg;
  const status = totals.failed > 0 ? "❌ FAIL" : "✅ PASS";

  const lines: string[] = [];
  lines.push("# Test Results Summary");
  lines.push("");
  lines.push(`**Status:** ${status}`);
  lines.push("");
  lines.push(`Aggregated **${fileCount} result file(s)**.`);
  lines.push("");

  // Totals table.
  lines.push("| Metric | Count |");
  lines.push("| --- | --- |");
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Duration | ${fmtDuration(totals.duration)} |`);
  lines.push("");

  // Flaky tests section.
  lines.push("## Flaky Tests");
  lines.push("");
  if (flaky.length === 0) {
    lines.push("No flaky tests detected. 🎉");
  } else {
    lines.push(
      `Found **${flaky.length}** flaky test(s) (passed in some runs, failed in others):`,
    );
    lines.push("");
    lines.push("| Test | Passed | Failed | Skipped |");
    lines.push("| --- | --- | --- | --- |");
    for (const f of flaky) {
      lines.push(`| ${f.id} | ${f.passed} | ${f.failed} | ${f.skipped} |`);
    }
  }
  lines.push("");

  return lines.join("\n");
}
