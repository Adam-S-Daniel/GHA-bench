/**
 * Markdown rendering: turn an `AggregateResult` into a GitHub-Actions-friendly
 * job-summary document.
 *
 * The output is plain GitHub-flavored markdown (tables + headings + a status
 * emoji) so it renders correctly both when written to `$GITHUB_STEP_SUMMARY`
 * and when viewed as a file. Pass rate is computed over *executed* tests
 * (passed + failed), excluding skips, since a skipped test neither passed nor
 * failed.
 */

import type { AggregateResult } from "./types.ts";

/** Format a duration in seconds with two decimals, e.g. "4.50s". */
function formatDuration(seconds: number): string {
  return `${seconds.toFixed(2)}s`;
}

/** Pass rate over executed (non-skipped) tests, as a one-decimal percent. */
function passRate(passed: number, failed: number): string {
  const executed = passed + failed;
  if (executed === 0) return "n/a";
  return `${((passed / executed) * 100).toFixed(1)}%`;
}

export function renderMarkdown(result: AggregateResult): string {
  const { totals, flaky, runCount } = result;
  const ok = totals.failed === 0;
  const badge = ok ? "✅" : "❌";
  const status = ok ? "All tests passing" : `${totals.failed} test(s) failing`;

  const lines: string[] = [];

  lines.push("# Test Results Summary");
  lines.push("");
  lines.push(
    `${badge} **${status}** across **${runCount} runs** ` +
      `in ${formatDuration(totals.duration)}.`,
  );
  lines.push("");

  // Totals table.
  lines.push("## Totals");
  lines.push("");
  lines.push("| Metric | Count |");
  lines.push("| --- | --- |");
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Pass rate | ${passRate(totals.passed, totals.failed)} |`);
  lines.push(`| Duration | ${formatDuration(totals.duration)} |`);
  lines.push("");

  // Flaky tests section.
  lines.push("## Flaky Tests");
  lines.push("");
  if (flaky.length === 0) {
    lines.push("No flaky tests detected. ✨");
  } else {
    lines.push(
      `Detected **${flaky.length}** flaky test(s) ` +
        `(passed in some runs, failed in others):`,
    );
    lines.push("");
    lines.push("| Test | Passed | Failed |");
    lines.push("| --- | --- | --- |");
    for (const f of flaky) {
      lines.push(`| ${f.id} | ${f.passed} | ${f.failed} |`);
    }
  }
  lines.push("");

  return lines.join("\n");
}
