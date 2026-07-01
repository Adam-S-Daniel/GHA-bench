import { describe, it, expect } from "bun:test";
import { generateMarkdownSummary } from "../src/markdown-report";
import type { AggregateResult } from "../src/types";

describe("generateMarkdownSummary", () => {
  it("renders totals table and a flaky tests section", () => {
    const result: AggregateResult = {
      totals: { passed: 2, failed: 1, skipped: 1, total: 4, duration: 4.5 },
      flakyTests: [
        {
          name: "flakyTest",
          suite: "S",
          outcomes: [
            { source: "run1.xml", status: "passed" },
            { source: "run2.xml", status: "failed" },
          ],
        },
      ],
      files: [],
    };

    const md = generateMarkdownSummary(result);

    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("| Passed | 2 |");
    expect(md).toContain("| Failed | 1 |");
    expect(md).toContain("| Skipped | 1 |");
    expect(md).toContain("| Total | 4 |");
    expect(md).toContain("4.5");
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("S/flakyTest");
    expect(md).toContain("run1.xml: passed");
    expect(md).toContain("run2.xml: failed");
  });

  it("omits the flaky tests section when there are none", () => {
    const result: AggregateResult = {
      totals: { passed: 1, failed: 0, skipped: 0, total: 1, duration: 0.1 },
      flakyTests: [],
      files: [],
    };

    const md = generateMarkdownSummary(result);
    expect(md).not.toContain("## Flaky Tests");
  });
});
