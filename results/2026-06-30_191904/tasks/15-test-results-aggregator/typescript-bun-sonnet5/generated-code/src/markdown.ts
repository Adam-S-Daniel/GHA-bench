import type { AggregatedResults } from "./types";

function countBySuite(suite: AggregatedResults["suites"][number]) {
  let passed = 0;
  let failed = 0;
  let skipped = 0;
  for (const t of suite.tests) {
    if (t.status === "passed") passed++;
    else if (t.status === "failed") failed++;
    else skipped++;
  }
  return { passed, failed, skipped };
}

/** Builds a GitHub Actions job-summary-ready markdown report from aggregated results. */
export function generateMarkdownSummary(result: AggregatedResults): string {
  const lines: string[] = [];

  lines.push("# Test Results Summary");
  lines.push("");
  lines.push(
    result.failed === 0
      ? "✅ All tests passed"
      : `❌ ${result.failed} test(s) failed`,
  );
  lines.push("");

  lines.push("| Metric | Count |");
  lines.push("| --- | --- |");
  lines.push(`| Total | ${result.totalTests} |`);
  lines.push(`| Passed | ${result.passed} |`);
  lines.push(`| Failed | ${result.failed} |`);
  lines.push(`| Skipped | ${result.skipped} |`);
  lines.push(`| Duration (s) | ${result.totalDuration.toFixed(3)} |`);
  lines.push("");

  lines.push("## Suites");
  lines.push("");
  lines.push("| Suite | Source | Passed | Failed | Skipped |");
  lines.push("| --- | --- | --- | --- | --- |");
  for (const suite of result.suites) {
    const { passed, failed, skipped } = countBySuite(suite);
    lines.push(`| ${suite.suiteName} | ${suite.source} | ${passed} | ${failed} | ${skipped} |`);
  }
  lines.push("");

  lines.push("## Flaky Tests");
  lines.push("");
  if (result.flakyTests.length === 0) {
    lines.push("No flaky tests detected.");
  } else {
    lines.push("| Test | Classname | Passed | Failed | Outcomes |");
    lines.push("| --- | --- | --- | --- | --- |");
    for (const flaky of result.flakyTests) {
      const outcomes = flaky.outcomes
        .map((o) => `${o.source}: ${o.status}`)
        .join(", ");
      lines.push(
        `| ${flaky.name} | ${flaky.classname} | ${flaky.passCount} | ${flaky.failCount} | ${outcomes} |`,
      );
    }
  }
  lines.push("");

  return lines.join("\n");
}
