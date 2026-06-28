/**
 * Markdown / machine-summary renderer tests (red/green TDD).
 *
 * Two renderers share the aggregate:
 *   - renderMarkdown:        human-facing GitHub job-summary markdown.
 *   - renderMachineSummary:  a stable key=value block used for CI assertions.
 */
import { describe, expect, test } from "bun:test";
import {
  renderMarkdown,
  renderMachineSummary,
  formatDuration,
} from "../src/markdown.ts";
import type { Aggregate } from "../src/types.ts";

const FAILED_AGG: Aggregate = {
  runCount: 3,
  totals: { passed: 10, failed: 2, skipped: 3, total: 15, duration: 3.0 },
  flaky: [
    { key: "MathSuite > test_divide", passed: 2, failed: 1 },
    { key: "MathSuite > test_subtract", passed: 2, failed: 1 },
  ],
};

const CLEAN_AGG: Aggregate = {
  runCount: 2,
  totals: { passed: 4, failed: 0, skipped: 0, total: 4, duration: 2.0 },
  flaky: [],
};

describe("formatDuration", () => {
  test("renders seconds with two decimals", () => {
    expect(formatDuration(3)).toBe("3.00s");
    expect(formatDuration(0.5)).toBe("0.50s");
  });
});

describe("renderMarkdown", () => {
  test("includes a heading and totals table", () => {
    const md = renderMarkdown(FAILED_AGG);
    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("| Passed | 10 |");
    expect(md).toContain("| Failed | 2 |");
    expect(md).toContain("| Skipped | 3 |");
    expect(md).toContain("| Total | 15 |");
    expect(md).toContain("| Duration | 3.00s |");
  });

  test("reports an overall FAILED verdict when there are failures", () => {
    expect(renderMarkdown(FAILED_AGG)).toContain("Overall: FAILED");
  });

  test("reports an overall PASSED verdict and no-flaky note when clean", () => {
    const md = renderMarkdown(CLEAN_AGG);
    expect(md).toContain("Overall: PASSED");
    expect(md).toContain("No flaky tests detected.");
  });

  test("lists each flaky test in the flaky table", () => {
    const md = renderMarkdown(FAILED_AGG);
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("| MathSuite > test_divide | 3 | 2 | 1 |");
    expect(md).toContain("| MathSuite > test_subtract | 3 | 2 | 1 |");
  });

  test("reports a NO TESTS verdict for an empty aggregate", () => {
    const empty: Aggregate = {
      runCount: 0,
      totals: { passed: 0, failed: 0, skipped: 0, total: 0, duration: 0 },
      flaky: [],
    };
    expect(renderMarkdown(empty)).toContain("Overall: NO TESTS");
  });
});

describe("renderMachineSummary", () => {
  test("emits a stable key=value block of totals", () => {
    const block = renderMachineSummary(FAILED_AGG);
    expect(block).toContain("runs=3");
    expect(block).toContain("passed=10");
    expect(block).toContain("failed=2");
    expect(block).toContain("skipped=3");
    expect(block).toContain("total=15");
    expect(block).toContain("duration=3.00");
    expect(block).toContain("flaky=2");
    expect(block).toContain("overall=FAILED");
  });

  test("emits a line for each flaky test", () => {
    const block = renderMachineSummary(FAILED_AGG);
    expect(block).toContain("flaky-test=MathSuite > test_divide");
    expect(block).toContain("flaky-test=MathSuite > test_subtract");
  });

  test("reports a passing verdict and zero flaky count for a clean run", () => {
    const block = renderMachineSummary(CLEAN_AGG);
    expect(block).toContain("overall=PASSED");
    expect(block).toContain("flaky=0");
  });

  test("is delimited so it can be located in noisy CI logs", () => {
    const block = renderMachineSummary(CLEAN_AGG);
    expect(block).toContain("=== AGGREGATE SUMMARY ===");
    expect(block).toContain("=== END SUMMARY ===");
  });
});
