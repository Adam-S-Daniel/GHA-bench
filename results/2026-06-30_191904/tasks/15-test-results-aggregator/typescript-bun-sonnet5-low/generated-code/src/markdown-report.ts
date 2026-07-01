import type { AggregateResult } from "./types";

// Renders an AggregateResult as GitHub-flavored markdown suitable for writing
// to $GITHUB_STEP_SUMMARY in a workflow job.

export function generateMarkdownSummary(result: AggregateResult): string {
  const { totals, flakyTests } = result;
  const status = totals.failed > 0 ? ":x: Failing" : ":white_check_mark: Passing";

  const lines: string[] = [];
  lines.push("# Test Results Summary");
  lines.push("");
  lines.push(`Overall status: ${status}`);
  lines.push("");
  lines.push("| Metric | Count |");
  lines.push("| --- | --- |");
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Duration (s) | ${totals.duration.toFixed(2)} |`);

  if (flakyTests.length > 0) {
    lines.push("");
    lines.push("## Flaky Tests");
    lines.push("");
    lines.push("The following tests had inconsistent results across runs:");
    lines.push("");
    for (const flaky of flakyTests) {
      lines.push(`- **${flaky.suite}/${flaky.name}**`);
      for (const outcome of flaky.outcomes) {
        lines.push(`  - ${outcome.source}: ${outcome.status}`);
      }
    }
  }

  lines.push("");
  return lines.join("\n");
}
