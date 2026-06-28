/**
 * Renderers that turn an {@link Aggregate} into output.
 *
 *   - renderMarkdown:       GitHub-flavored markdown for a job summary
 *                           (written to $GITHUB_STEP_SUMMARY).
 *   - renderMachineSummary: a delimited key=value block that downstream
 *                           tooling / CI assertions can grep reliably, even
 *                           when interleaved with other build log noise.
 *
 * No emojis are used, keeping the output easy to assert on and readable in
 * plain-text logs.
 */
import type { Aggregate } from "./types.ts";

/** Format a duration in seconds as a fixed two-decimal seconds string. */
export function formatDuration(seconds: number): string {
  return `${seconds.toFixed(2)}s`;
}

/** Derive the overall verdict from the totals. */
function verdict(agg: Aggregate): "PASSED" | "FAILED" | "NO TESTS" {
  if (agg.totals.total === 0) return "NO TESTS";
  return agg.totals.failed > 0 ? "FAILED" : "PASSED";
}

/** Render the human-facing GitHub Actions job summary markdown. */
export function renderMarkdown(agg: Aggregate): string {
  const { totals, flaky, runCount } = agg;
  const lines: string[] = [];

  lines.push("# Test Results Summary");
  lines.push("");
  lines.push(
    `Aggregated **${runCount}** run(s) — **${totals.total}** test executions.`,
  );
  lines.push("");

  lines.push("## Totals");
  lines.push("");
  lines.push("| Result | Count |");
  lines.push("| --- | ---: |");
  lines.push(`| Passed | ${totals.passed} |`);
  lines.push(`| Failed | ${totals.failed} |`);
  lines.push(`| Skipped | ${totals.skipped} |`);
  lines.push(`| Total | ${totals.total} |`);
  lines.push(`| Duration | ${formatDuration(totals.duration)} |`);
  lines.push("");

  const overall = verdict(agg);
  if (overall === "FAILED") {
    lines.push(`**Overall: FAILED** — ${totals.failed} failed across ${runCount} run(s).`);
  } else if (overall === "PASSED") {
    lines.push(`**Overall: PASSED** — all ${totals.passed} executed tests passed.`);
  } else {
    lines.push("**Overall: NO TESTS** — no test results were found.");
  }
  lines.push("");

  lines.push("## Flaky Tests");
  lines.push("");
  if (flaky.length === 0) {
    lines.push("No flaky tests detected.");
  } else {
    lines.push(
      `${flaky.length} test(s) passed in some runs and failed in others:`,
    );
    lines.push("");
    lines.push("| Test | Runs | Passed | Failed |");
    lines.push("| --- | ---: | ---: | ---: |");
    for (const f of flaky) {
      const runs = f.passed + f.failed;
      lines.push(`| ${f.key} | ${runs} | ${f.passed} | ${f.failed} |`);
    }
  }
  lines.push("");

  return lines.join("\n");
}

/**
 * Render a stable, delimited key=value block. The aggregator sorts flaky tests,
 * so this output is deterministic for a given input — ideal for exact-match
 * assertions in the CI test harness.
 */
export function renderMachineSummary(agg: Aggregate): string {
  const { totals, flaky, runCount } = agg;
  const lines: string[] = [];
  lines.push("=== AGGREGATE SUMMARY ===");
  lines.push(`runs=${runCount}`);
  lines.push(`passed=${totals.passed}`);
  lines.push(`failed=${totals.failed}`);
  lines.push(`skipped=${totals.skipped}`);
  lines.push(`total=${totals.total}`);
  lines.push(`duration=${totals.duration.toFixed(2)}`);
  lines.push(`flaky=${flaky.length}`);
  for (const f of flaky) {
    lines.push(`flaky-test=${f.key}`);
  }
  lines.push(`overall=${verdict(agg)}`);
  lines.push("=== END SUMMARY ===");
  return lines.join("\n");
}
