import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregator.ts";
import type { ParsedFile } from "../src/types.ts";

// Helper to build a ParsedFile concisely.
function file(source: string, ...rows: Array<[string, string, string, number]>): ParsedFile {
  return {
    source,
    results: rows.map(([suite, name, status, duration]) => ({
      suite,
      name,
      status: status as any,
      duration,
    })),
  };
}

describe("aggregate", () => {
  test("computes totals across multiple files", () => {
    const files: ParsedFile[] = [
      file("run1.xml", ["S", "a", "passed", 1], ["S", "b", "failed", 2]),
      file("run2.json", ["S", "a", "passed", 1], ["S", "c", "skipped", 0]),
    ];
    const agg = aggregate(files);
    expect(agg.totals).toEqual({
      passed: 2,
      failed: 1,
      skipped: 1,
      total: 4,
      duration: 4,
    });
    expect(agg.fileCount).toBe(2);
  });

  test("identifies a flaky test that passes in one run and fails in another", () => {
    const files: ParsedFile[] = [
      file("run1.xml", ["S", "flaky", "passed", 1]),
      file("run2.xml", ["S", "flaky", "failed", 1]),
      file("run3.xml", ["S", "flaky", "passed", 1]),
    ];
    const agg = aggregate(files);
    expect(agg.flaky).toHaveLength(1);
    expect(agg.flaky[0]).toEqual({
      id: "S > flaky",
      suite: "S",
      name: "flaky",
      passed: 2,
      failed: 1,
      skipped: 0,
    });
  });

  test("does not flag consistently-passing or consistently-failing tests as flaky", () => {
    const files: ParsedFile[] = [
      file("a.xml", ["S", "stable", "passed", 1], ["S", "broken", "failed", 1]),
      file("b.xml", ["S", "stable", "passed", 1], ["S", "broken", "failed", 1]),
    ];
    const agg = aggregate(files);
    expect(agg.flaky).toHaveLength(0);
  });

  test("sorts flaky tests by failure count descending", () => {
    const files: ParsedFile[] = [
      file("a.xml", ["S", "x", "passed", 1], ["S", "y", "passed", 1]),
      file("b.xml", ["S", "x", "failed", 1], ["S", "y", "failed", 1]),
      file("c.xml", ["S", "y", "failed", 1]),
    ];
    const agg = aggregate(files);
    expect(agg.flaky.map((f) => f.name)).toEqual(["y", "x"]);
  });

  test("treats same name in different suites as distinct tests", () => {
    const files: ParsedFile[] = [
      file("a.xml", ["S1", "t", "passed", 1], ["S2", "t", "failed", 1]),
      file("b.xml", ["S1", "t", "passed", 1], ["S2", "t", "failed", 1]),
    ];
    const agg = aggregate(files);
    expect(agg.flaky).toHaveLength(0);
  });
});
