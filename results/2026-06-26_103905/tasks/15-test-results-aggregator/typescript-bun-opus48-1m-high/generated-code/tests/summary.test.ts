import { describe, expect, it } from "bun:test";
import { renderMarkdown } from "../src/summary.ts";
import type { AggregateResult } from "../src/types.ts";

const base: AggregateResult = {
  totals: { passed: 10, failed: 2, skipped: 1, total: 13, duration: 4.5 },
  flaky: [],
  runCount: 3,
};

describe("renderMarkdown", () => {
  it("includes a heading and a totals table with counts", () => {
    const md = renderMarkdown(base);
    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("| Passed | 10 |");
    expect(md).toContain("| Failed | 2 |");
    expect(md).toContain("| Skipped | 1 |");
    expect(md).toContain("| Total | 13 |");
  });

  it("reports the run count and formats duration in seconds", () => {
    const md = renderMarkdown(base);
    expect(md).toContain("3 runs");
    expect(md).toContain("4.50s");
  });

  it("shows a passing status badge when there are no failures", () => {
    const md = renderMarkdown({
      ...base,
      totals: { passed: 5, failed: 0, skipped: 0, total: 5, duration: 1 },
    });
    expect(md).toContain("✅");
    expect(md).not.toContain("❌");
  });

  it("shows a failing status badge when there are failures", () => {
    const md = renderMarkdown(base);
    expect(md).toContain("❌");
  });

  it("renders a flaky-tests section listing each flaky test", () => {
    const md = renderMarkdown({
      ...base,
      flaky: [
        { id: "auth > login", passed: 2, failed: 1 },
        { id: "net > fetch", passed: 1, failed: 3 },
      ],
    });
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("auth > login");
    expect(md).toContain("net > fetch");
    // pass/fail counts for a flaky row appear
    expect(md).toMatch(/auth > login.*\|\s*2\s*\|\s*1\s*\|/);
  });

  it("states there are no flaky tests when the list is empty", () => {
    const md = renderMarkdown(base);
    expect(md).toContain("No flaky tests detected");
  });

  it("computes a pass rate percentage", () => {
    // 10 passed of (10 passed + 2 failed) executed = 83.3%
    const md = renderMarkdown(base);
    expect(md).toContain("83.3%");
  });
});
