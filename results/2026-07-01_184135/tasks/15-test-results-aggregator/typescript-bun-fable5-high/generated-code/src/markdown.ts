/**
 * Markdown summary renderer for GitHub Actions job summaries.
 *
 * Approach: build the document as an array of lines and join once. Sections
 * for flaky/failing tests are omitted entirely when empty so a green build
 * reads as a short, positive summary rather than a wall of empty tables.
 */
import type { AggregateReport } from "./types";

/** Escape characters that would break a GitHub markdown table cell. */
function cell(text: string): string {
  return text.replace(/\|/g, "\\|").replace(/\r?\n/g, " ");
}

function seconds(n: number): string {
  return `${n.toFixed(2)}s`;
}

export function renderMarkdownSummary(report: AggregateReport): string {
  const { totals, perRun, flaky, failed } = report;
  const lines: string[] = [];

  lines.push("# 🧪 Test Results", "");

  // Headline verdict before any tables — the one-glance takeaway.
  if (totals.failed === 0 && flaky.length === 0) {
    lines.push(`✅ All ${totals.passed} tests passed.`, "");
  } else {
    lines.push(
      `❌ ${totals.failed} of ${totals.total} test results failed` +
        (flaky.length > 0 ? ` (${flaky.length} flaky)` : "") +
        ".",
      "",
    );
  }

  lines.push(
    "| Status | Count |",
    "| --- | ---: |",
    `| ✅ Passed | ${totals.passed} |`,
    `| ❌ Failed | ${totals.failed} |`,
    `| ⏭️ Skipped | ${totals.skipped} |`,
    `| **Total** | **${totals.total}** |`,
    "",
    `**Total duration:** ${seconds(totals.durationSeconds)} across ${perRun.length} runs`,
    "",
  );

  if (flaky.length > 0) {
    lines.push(
      `## ⚠️ Flaky tests (${flaky.length})`,
      "",
      "Passed in some runs but failed in others — likely nondeterministic.",
      "",
      "| Test | Passed in | Failed in |",
      "| --- | --- | --- |",
      ...flaky.map(
        (t) => `| \`${cell(t.id)}\` | ${cell(t.passedIn.join(", "))} | ${cell(t.failedIn.join(", "))} |`,
      ),
      "",
    );
  } else {
    lines.push("No flaky tests detected.", "");
  }

  if (failed.length > 0) {
    lines.push(
      `## ❌ Failing tests (${failed.length})`,
      "",
      "| Test | Failed in | Message |",
      "| --- | --- | --- |",
      ...failed.map(
        (t) => `| \`${cell(t.id)}\` | ${cell(t.failedIn.join(", "))} | ${cell(t.message ?? "—")} |`,
      ),
      "",
    );
  }

  lines.push(
    "## 📊 Per-run breakdown",
    "",
    "| Run | Total | Passed | Failed | Skipped | Duration |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
    ...perRun.map(
      (r) =>
        `| ${cell(r.source)} | ${r.totals.total} | ${r.totals.passed} | ${r.totals.failed} | ${r.totals.skipped} | ${seconds(r.totals.durationSeconds)} |`,
    ),
    "",
  );

  return lines.join("\n");
}
