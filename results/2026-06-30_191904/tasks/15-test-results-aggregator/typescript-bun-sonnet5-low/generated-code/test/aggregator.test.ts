import { describe, it, expect } from "bun:test";
import { aggregate } from "../src/aggregator";
import type { ParsedFile } from "../src/types";

describe("aggregate", () => {
  it("computes totals across multiple files", () => {
    const files: ParsedFile[] = [
      {
        source: "run1.xml",
        tests: [
          { name: "a", suite: "S", status: "passed", duration: 1 },
          { name: "b", suite: "S", status: "failed", duration: 2 },
        ],
      },
      {
        source: "run2.xml",
        tests: [
          { name: "a", suite: "S", status: "passed", duration: 1.5 },
          { name: "c", suite: "S", status: "skipped", duration: 0 },
        ],
      },
    ];

    const result = aggregate(files);

    expect(result.totals.passed).toBe(2);
    expect(result.totals.failed).toBe(1);
    expect(result.totals.skipped).toBe(1);
    expect(result.totals.total).toBe(4);
    expect(result.totals.duration).toBeCloseTo(4.5);
  });

  it("identifies flaky tests that pass in one run and fail in another", () => {
    const files: ParsedFile[] = [
      {
        source: "run1.xml",
        tests: [{ name: "flakyTest", suite: "S", status: "passed", duration: 0.1 }],
      },
      {
        source: "run2.xml",
        tests: [{ name: "flakyTest", suite: "S", status: "failed", duration: 0.1 }],
      },
      {
        source: "run3.xml",
        tests: [{ name: "stableTest", suite: "S", status: "passed", duration: 0.1 }],
      },
    ];

    const result = aggregate(files);

    expect(result.flakyTests).toHaveLength(1);
    expect(result.flakyTests[0].name).toBe("flakyTest");
    expect(result.flakyTests[0].outcomes).toEqual([
      { source: "run1.xml", status: "passed" },
      { source: "run2.xml", status: "failed" },
    ]);
  });

  it("does not flag a test that is consistently failing across all runs", () => {
    const files: ParsedFile[] = [
      { source: "run1.xml", tests: [{ name: "alwaysFails", suite: "S", status: "failed", duration: 0.1 }] },
      { source: "run2.xml", tests: [{ name: "alwaysFails", suite: "S", status: "failed", duration: 0.1 }] },
    ];

    const result = aggregate(files);
    expect(result.flakyTests).toHaveLength(0);
  });
});
