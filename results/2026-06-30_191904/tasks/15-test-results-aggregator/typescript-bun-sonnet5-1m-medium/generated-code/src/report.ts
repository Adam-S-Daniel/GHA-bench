// Renders an AggregateResult as GitHub-flavored markdown suitable for
// $GITHUB_STEP_SUMMARY.

import type { AggregateResult } from "./types";

export function generateMarkdownSummary(result: AggregateResult): string {
  const { files, totals, flakyTests } = result;
  const statusBadge = totals.failed > 0 ? "❌" : "✅";

  const lines: string[] = [];

  lines.push(`# Test Results Summary ${statusBadge}`, "");

  lines.push("## Totals", "");
  lines.push("| Metric | Count |", "| --- | --- |");
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Duration | ${totals.duration.toFixed(2)}s |`, "");

  lines.push("## Source Files", "");
  for (const file of files) {
    lines.push(`- \`${file.source}\` (${file.format}, ${file.tests.length} tests)`);
  }
  lines.push("");

  if (flakyTests.length > 0) {
    lines.push("## Flaky Tests", "");
    lines.push("Tests whose outcome differed across runs:", "");
    for (const flaky of flakyTests) {
      lines.push(`- **${flaky.suite} > ${flaky.name}**`);
      for (const outcome of flaky.outcomes) {
        lines.push(`  - ${outcome.source}: ${outcome.status}`);
      }
    }
    lines.push("");
  }

  return lines.join("\n");
}
