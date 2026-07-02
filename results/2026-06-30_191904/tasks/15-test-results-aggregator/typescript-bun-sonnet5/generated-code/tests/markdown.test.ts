import { describe, expect, test } from "bun:test";
import { generateMarkdownSummary } from "../src/markdown";
import type { AggregatedResults } from "../src/types";

const baseSuites: AggregatedResults["suites"] = [
  {
    suiteName: "UnitTests",
    source: "run1.xml",
    tests: [
      { name: "t1", classname: "C", status: "passed", duration: 0.1 },
      { name: "t2", classname: "C", status: "failed", duration: 0.2, message: "boom" },
    ],
  },
];

describe("generateMarkdownSummary", () => {
  test("renders a success header and totals table when there are no failures", () => {
    const result: AggregatedResults = {
      totalTests: 2,
      passed: 2,
      failed: 0,
      skipped: 0,
      totalDuration: 0.3,
      suites: baseSuites,
      flakyTests: [],
    };

    const md = generateMarkdownSummary(result);

    expect(md).toContain("# Test Results Summary");
    expect(md).toContain("✅ All tests passed");
    expect(md).toContain("| Total | 2 |");
    expect(md).toContain("| Passed | 2 |");
    expect(md).toContain("| Failed | 0 |");
    expect(md).toContain("| Skipped | 0 |");
    expect(md).toContain("No flaky tests detected");
  });

  test("renders a failure header when there are failures", () => {
    const result: AggregatedResults = {
      totalTests: 2,
      passed: 1,
      failed: 1,
      skipped: 0,
      totalDuration: 0.3,
      suites: baseSuites,
      flakyTests: [],
    };

    const md = generateMarkdownSummary(result);
    expect(md).toContain("❌ 1 test(s) failed");
  });

  test("lists flaky tests in a dedicated section", () => {
    const result: AggregatedResults = {
      totalTests: 2,
      passed: 1,
      failed: 1,
      skipped: 0,
      totalDuration: 0.3,
      suites: baseSuites,
      flakyTests: [
        {
          suiteName: "UnitTests",
          classname: "C",
          name: "testFlaky",
          outcomes: [
            { source: "run1.xml", status: "failed" },
            { source: "run2.xml", status: "passed" },
          ],
          passCount: 1,
          failCount: 1,
        },
      ],
    };

    const md = generateMarkdownSummary(result);
    expect(md).toContain("## Flaky Tests");
    expect(md).toContain("testFlaky");
    expect(md).toContain("C");
    expect(md).not.toContain("No flaky tests detected");
  });

  test("includes a per-suite breakdown table", () => {
    const result: AggregatedResults = {
      totalTests: 2,
      passed: 1,
      failed: 1,
      skipped: 0,
      totalDuration: 0.3,
      suites: baseSuites,
      flakyTests: [],
    };

    const md = generateMarkdownSummary(result);
    expect(md).toContain("## Suites");
    expect(md).toContain("run1.xml");
    expect(md).toContain("UnitTests");
  });
});
