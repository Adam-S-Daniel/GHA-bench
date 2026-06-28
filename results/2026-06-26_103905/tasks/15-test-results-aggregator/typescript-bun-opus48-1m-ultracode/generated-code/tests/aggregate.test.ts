/**
 * Tests for aggregation: totals across the whole matrix and flaky-test
 * detection (a test that passed in some runs and failed in others).
 */
import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregate";
import type { TestRun } from "../src/types";

/** Build a run quickly from terse tuples to keep the tests readable. */
function run(
  source: string,
  name: string,
  cases: Array<[string, string, "passed" | "failed" | "skipped", number]>,
): TestRun {
  return {
    source,
    name,
    cases: cases.map(([suite, testName, status, durationSeconds]) => ({
      suite,
      name: testName,
      status,
      durationSeconds,
    })),
  };
}

describe("aggregate", () => {
  test("sums totals and duration across every run", () => {
    const runs: TestRun[] = [
      run("run1.json", "linux", [
        ["Math", "adds", "passed", 0.1],
        ["Math", "divides", "failed", 0.2],
        ["Math", "todo", "skipped", 0],
      ]),
      run("run2.xml", "windows", [
        ["Math", "adds", "passed", 0.15],
        ["Math", "divides", "passed", 0.25],
      ]),
    ];

    const result = aggregate(runs);

    expect(result.runCount).toBe(2);
    expect(result.totals).toEqual({
      passed: 3,
      failed: 1,
      skipped: 1,
      total: 5,
      durationSeconds: 0.7,
    });
    // Overall verdict is "not passed" because there was at least one failure.
    expect(result.passed).toBe(false);
  });

  test("flags a test that passed in one run and failed in another as flaky", () => {
    const runs: TestRun[] = [
      run("run1.json", "linux", [
        ["Net", "fetches", "passed", 0.1],
        ["Net", "stable", "passed", 0.1],
      ]),
      run("run2.json", "macos", [
        ["Net", "fetches", "failed", 0.1],
        ["Net", "stable", "passed", 0.1],
      ]),
      run("run3.json", "windows", [
        ["Net", "fetches", "passed", 0.1],
        ["Net", "stable", "passed", 0.1],
      ]),
    ];

    const result = aggregate(runs);

    expect(result.flaky).toHaveLength(1);
    const flaky = result.flaky[0]!;
    expect(flaky.key).toBe("Net::fetches");
    expect(flaky.name).toBe("fetches");
    expect(flaky.suite).toBe("Net");
    expect(flaky.passed).toBe(2);
    expect(flaky.failed).toBe(1);
    expect(flaky.appearances).toBe(3);
  });

  test("a test that is always failing is NOT flaky", () => {
    const runs: TestRun[] = [
      run("a.json", "a", [["S", "broken", "failed", 0]]),
      run("b.json", "b", [["S", "broken", "failed", 0]]),
    ];
    const result = aggregate(runs);
    expect(result.flaky).toHaveLength(0);
    expect(result.totals.failed).toBe(2);
  });

  test("a skipped-then-passed test is not flaky (no failure involved)", () => {
    const runs: TestRun[] = [
      run("a.json", "a", [["S", "sometimes", "skipped", 0]]),
      run("b.json", "b", [["S", "sometimes", "passed", 0]]),
    ];
    expect(aggregate(runs).flaky).toHaveLength(0);
  });

  test("sorts flaky tests by failure count descending then by key", () => {
    const runs: TestRun[] = [
      run("r1.json", "r1", [
        ["S", "a", "passed", 0],
        ["S", "b", "passed", 0],
      ]),
      run("r2.json", "r2", [
        ["S", "a", "failed", 0],
        ["S", "b", "failed", 0],
      ]),
      run("r3.json", "r3", [
        ["S", "a", "passed", 0],
        ["S", "b", "failed", 0],
      ]),
    ];
    const flaky = aggregate(runs).flaky;
    // "b" failed twice, "a" failed once -> b first.
    expect(flaky.map((f) => f.key)).toEqual(["S::b", "S::a"]);
  });

  test("produces a per-run summary in input order", () => {
    const runs: TestRun[] = [
      run("first.json", "first", [["S", "x", "passed", 0.5]]),
      run("second.json", "second", [["S", "y", "failed", 0.25]]),
    ];
    const summaries = aggregate(runs).runs;
    expect(summaries).toHaveLength(2);
    expect(summaries[0]).toEqual({
      source: "first.json",
      name: "first",
      passed: 1,
      failed: 0,
      skipped: 0,
      durationSeconds: 0.5,
    });
    expect(summaries[1]?.failed).toBe(1);
  });

  test("an all-green matrix reports passed: true and no flaky tests", () => {
    const runs: TestRun[] = [
      run("a.json", "a", [["S", "x", "passed", 0.1]]),
      run("b.json", "b", [["S", "x", "passed", 0.1]]),
    ];
    const result = aggregate(runs);
    expect(result.passed).toBe(true);
    expect(result.flaky).toHaveLength(0);
    expect(result.totals.failed).toBe(0);
  });
});
