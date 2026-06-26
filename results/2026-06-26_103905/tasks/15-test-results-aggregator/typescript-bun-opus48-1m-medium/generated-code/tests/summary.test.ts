import { describe, expect, test } from "bun:test";
import { renderSummary } from "../src/summary.ts";
import type { Aggregation } from "../src/types.ts";

const baseAgg: Aggregation = {
  totals: { passed: 10, failed: 2, skipped: 1, total: 13, duration: 12.5 },
  flaky: [
    { id: "S > flaky", suite: "S", name: "flaky", passed: 2, failed: 1, skipped: 0 },
  ],
  fileCount: 3,
};

describe("renderSummary", () => {
  test("includes a heading and the totals table", () => {
    const md = renderSummary(baseAgg);
    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("| Passed | 10 |");
    expect(md).toContain("| Failed | 2 |");
    expect(md).toContain("| Skipped | 1 |");
    expect(md).toContain("| Total | 13 |");
  });

  test("formats duration in seconds with two decimals", () => {
    const md = renderSummary(baseAgg);
    expect(md).toContain("12.50s");
  });

  test("reports the number of aggregated files", () => {
    const md = renderSummary(baseAgg);
    expect(md).toContain("3 result file(s)");
  });

  test("renders a flaky-tests section listing each flaky test", () => {
    const md = renderSummary(baseAgg);
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("S > flaky");
    // passed/failed counts appear in the row
    expect(md).toMatch(/S > flaky.*\|\s*2\s*\|\s*1\s*\|/);
  });

  test("shows a clean-bill message when there are no flaky tests", () => {
    const md = renderSummary({ ...baseAgg, flaky: [] });
    expect(md).toContain("No flaky tests detected");
    expect(md).not.toContain("## Flaky Tests\n\n|");
  });

  test("shows an overall PASS status when nothing failed", () => {
    const md = renderSummary({
      ...baseAgg,
      totals: { passed: 5, failed: 0, skipped: 0, total: 5, duration: 1 },
      flaky: [],
    });
    expect(md).toMatch(/Status.*PASS/);
  });

  test("shows an overall FAIL status when something failed", () => {
    const md = renderSummary(baseAgg);
    expect(md).toMatch(/Status.*FAIL/);
  });
});
