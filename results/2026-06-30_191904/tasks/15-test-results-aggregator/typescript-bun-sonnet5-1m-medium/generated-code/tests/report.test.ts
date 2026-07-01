import { describe, expect, test } from "bun:test";
import { generateMarkdownSummary } from "../src/report";
import type { AggregateResult } from "../src/types";

function makeResult(overrides: Partial<AggregateResult> = {}): AggregateResult {
  return {
    files: [
      { source: "run-a.xml", format: "junit", tests: [] },
      { source: "run-b.json", format: "json", tests: [] },
    ],
    totals: { total: 10, passed: 7, failed: 2, skipped: 1, duration: 12.345 },
    flakyTests: [
      {
        suite: "MathUtils",
        name: "adds two numbers",
        outcomes: [
          { source: "run-a.xml", status: "passed" },
          { source: "run-b.json", status: "failed" },
        ],
      },
    ],
    ...overrides,
  };
}

describe("generateMarkdownSummary", () => {
  test("includes a heading and totals table", () => {
    const md = generateMarkdownSummary(makeResult());

    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("| Total | 10 |");
    expect(md).toContain("| Passed | 7 |");
    expect(md).toContain("| Failed | 2 |");
    expect(md).toContain("| Skipped | 1 |");
    expect(md).toContain("12.35s");
  });

  test("lists the source files that were aggregated", () => {
    const md = generateMarkdownSummary(makeResult());
    expect(md).toContain("run-a.xml");
    expect(md).toContain("run-b.json");
  });

  test("includes a flaky tests section with per-source outcomes", () => {
    const md = generateMarkdownSummary(makeResult());
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("adds two numbers");
    expect(md).toContain("MathUtils");
    expect(md).toContain("run-a.xml: passed");
    expect(md).toContain("run-b.json: failed");
  });

  test("omits the flaky tests section entirely when there are none", () => {
    const md = generateMarkdownSummary(makeResult({ flakyTests: [] }));
    expect(md).not.toContain("## Flaky Tests");
  });

  test("shows a passing status badge when there are no failures", () => {
    const md = generateMarkdownSummary(
      makeResult({ totals: { total: 5, passed: 5, failed: 0, skipped: 0, duration: 1 }, flakyTests: [] }),
    );
    expect(md).toContain("✅");
  });

  test("shows a failing status badge when there are failures", () => {
    const md = generateMarkdownSummary(makeResult());
    expect(md).toContain("❌");
  });
});
