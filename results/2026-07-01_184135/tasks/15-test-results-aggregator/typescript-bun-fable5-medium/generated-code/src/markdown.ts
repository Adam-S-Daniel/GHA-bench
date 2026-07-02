/**
 * Markdown summary renderer.
 *
 * Produces GitHub-flavored markdown intended for $GITHUB_STEP_SUMMARY:
 * a status line, a totals table, and (only when relevant) a flaky-tests table.
 */
import type { AggregateSummary } from "./types";

/** Overall status line: failure > empty > success, in that priority. */
function statusLine(summary: AggregateSummary): string {
  if (summary.total === 0) return "**Status:** ⚠️ No test results found";
  if (summary.failed > 0)
    return `**Status:** ❌ ${summary.failed} test(s) failed`;
  return "**Status:** ✅ All tests passed";
}

/** Render the aggregate summary as GitHub-flavored markdown. */
export function renderMarkdownSummary(summary: AggregateSummary): string {
  const lines: string[] = [
    "# 🧪 Test Results Summary",
    "",
    statusLine(summary),
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    `| Total tests | ${summary.total} |`,
    `| ✅ Passed | ${summary.passed} |`,
    `| ❌ Failed | ${summary.failed} |`,
    `| ⏭️ Skipped | ${summary.skipped} |`,
    `| ⏱️ Duration | ${summary.durationSec.toFixed(2)}s |`,
    `| 📄 Result files | ${summary.files} |`,
  ];

  if (summary.flaky.length > 0) {
    lines.push(
      "",
      `## ⚠️ Flaky tests (${summary.flaky.length})`,
      "",
      "These tests passed in some runs and failed in others:",
      "",
      "| Test | Passed | Failed |",
      "| --- | ---: | ---: |",
      ...summary.flaky.map((f) => `| \`${f.id}\` | ${f.passes} | ${f.failures} |`),
    );
  }

  lines.push("");
  return lines.join("\n");
}
