/**
 * Markdown renderer for the GitHub Actions job summary.
 *
 * The output is intentionally plain (no emoji, GitHub-Flavoured-Markdown
 * tables) so it renders cleanly in a job summary AND so its exact lines are
 * easy to assert on from the act-driven integration tests. Numeric columns are
 * right-aligned with `---:`.
 */
import type { AggregateResult } from "./types";

/** Format a duration in seconds as a fixed, 3-decimal value with a unit. */
export function formatDuration(seconds: number): string {
  return `${seconds.toFixed(3)}s`;
}

/** Escape the pipe character so test names never break a table cell. */
function escapeCell(value: string): string {
  return value.replace(/\|/g, "\\|");
}

/** Prefer the run's declared name; fall back to its source path. */
function runLabel(name: string, source: string): string {
  return name.length > 0 ? name : source;
}

/**
 * Render the full aggregate result as a markdown document suitable for
 * `$GITHUB_STEP_SUMMARY`.
 */
export function renderMarkdown(result: AggregateResult): string {
  const { totals, flaky, runs } = result;
  const status = result.passed ? "PASSED" : "FAILED";
  const lines: string[] = [];

  // --- Heading + one-line verdict -----------------------------------------
  lines.push("## Test Results Summary");
  lines.push("");
  lines.push(
    `**Result:** ${status} — ${totals.passed} passed, ${totals.failed} failed, ` +
      `${totals.skipped} skipped (${totals.total} total) across ${result.runCount} ` +
      `run${result.runCount === 1 ? "" : "s"} in ${formatDuration(totals.durationSeconds)}.`,
  );
  lines.push("");

  // --- Totals table -------------------------------------------------------
  lines.push("| Metric | Count |");
  lines.push("| --- | ---: |");
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Duration | ${formatDuration(totals.durationSeconds)} |`);
  lines.push("");

  // --- Flaky tests --------------------------------------------------------
  if (flaky.length === 0) {
    lines.push("No flaky tests detected.");
  } else {
    lines.push(`### Flaky Tests (${flaky.length})`);
    lines.push("");
    lines.push("These tests passed in some runs and failed in others:");
    lines.push("");
    lines.push("| Test | Passed | Failed | Runs |");
    lines.push("| --- | ---: | ---: | ---: |");
    for (const f of flaky) {
      lines.push(`| ${escapeCell(f.key)} | ${f.passed} | ${f.failed} | ${f.appearances} |`);
    }
  }
  lines.push("");

  // --- Per-run breakdown --------------------------------------------------
  lines.push("### Per-Run Breakdown");
  lines.push("");
  lines.push("| Run | Passed | Failed | Skipped | Duration |");
  lines.push("| --- | ---: | ---: | ---: | ---: |");
  for (const r of runs) {
    lines.push(
      `| ${escapeCell(runLabel(r.name, r.source))} | ${r.passed} | ${r.failed} | ` +
        `${r.skipped} | ${formatDuration(r.durationSeconds)} |`,
    );
  }
  lines.push("");

  return lines.join("\n");
}
