/**
 * Aggregator tests (red/green TDD).
 *
 * The aggregator folds many runs into totals + a flaky-test list. We assert
 * exact counts so the behaviour is pinned down precisely.
 */
import { describe, expect, test } from "bun:test";
import { aggregate, testKey } from "../src/aggregator.ts";
import type { TestRun } from "../src/types.ts";

function run(source: string, cases: TestRun["cases"]): TestRun {
  return { source, cases };
}

describe("testKey", () => {
  test("combines suite and name when a suite is present", () => {
    expect(testKey({ name: "t", suite: "S", status: "passed", duration: 0 })).toBe(
      "S > t",
    );
  });
  test("uses the name alone when no suite is present", () => {
    expect(testKey({ name: "t", status: "passed", duration: 0 })).toBe("t");
  });
});

describe("aggregate totals", () => {
  test("sums passed/failed/skipped/total/duration across runs", () => {
    const runs: TestRun[] = [
      run("a", [
        { name: "x", status: "passed", duration: 0.5 },
        { name: "y", status: "failed", duration: 0.25 },
        { name: "z", status: "skipped", duration: 0 },
      ]),
      run("b", [
        { name: "x", status: "passed", duration: 0.5 },
        { name: "y", status: "passed", duration: 0.25 },
      ]),
    ];
    const agg = aggregate(runs);
    expect(agg.runCount).toBe(2);
    expect(agg.totals.passed).toBe(3);
    expect(agg.totals.failed).toBe(1);
    expect(agg.totals.skipped).toBe(1);
    expect(agg.totals.total).toBe(5);
    expect(agg.totals.duration).toBeCloseTo(1.5, 5);
  });

  test("handles an empty set of runs", () => {
    const agg = aggregate([]);
    expect(agg.runCount).toBe(0);
    expect(agg.totals.total).toBe(0);
    expect(agg.flaky).toHaveLength(0);
  });
});

describe("flaky detection", () => {
  test("flags a test that passed in one run and failed in another", () => {
    const runs: TestRun[] = [
      run("a", [{ name: "t", suite: "S", status: "passed", duration: 0.1 }]),
      run("b", [{ name: "t", suite: "S", status: "failed", duration: 0.1 }]),
    ];
    const agg = aggregate(runs);
    expect(agg.flaky).toHaveLength(1);
    expect(agg.flaky[0]!.key).toBe("S > t");
    expect(agg.flaky[0]!.passed).toBe(1);
    expect(agg.flaky[0]!.failed).toBe(1);
  });

  test("does not flag consistently-passing or consistently-failing tests", () => {
    const runs: TestRun[] = [
      run("a", [
        { name: "stable_pass", status: "passed", duration: 0.1 },
        { name: "stable_fail", status: "failed", duration: 0.1 },
      ]),
      run("b", [
        { name: "stable_pass", status: "passed", duration: 0.1 },
        { name: "stable_fail", status: "failed", duration: 0.1 },
      ]),
    ];
    expect(aggregate(runs).flaky).toHaveLength(0);
  });

  test("skips do not make a test flaky", () => {
    const runs: TestRun[] = [
      run("a", [{ name: "t", status: "passed", duration: 0.1 }]),
      run("b", [{ name: "t", status: "skipped", duration: 0 }]),
    ];
    expect(aggregate(runs).flaky).toHaveLength(0);
  });

  test("returns flaky tests sorted by key", () => {
    const runs: TestRun[] = [
      run("a", [
        { name: "zebra", status: "passed", duration: 0 },
        { name: "apple", status: "passed", duration: 0 },
      ]),
      run("b", [
        { name: "zebra", status: "failed", duration: 0 },
        { name: "apple", status: "failed", duration: 0 },
      ]),
    ];
    const agg = aggregate(runs);
    expect(agg.flaky.map((f) => f.key)).toEqual(["apple", "zebra"]);
  });

  test("counts the canonical 3-run matrix fixture correctly", () => {
    // Mirrors fixtures/sample: divide flaky (P,F,P), subtract flaky (P,P,F).
    const runs: TestRun[] = [
      run("r1", [
        { name: "test_divide", suite: "MathSuite", status: "passed", duration: 0.3 },
        { name: "test_subtract", suite: "MathSuite", status: "passed", duration: 0.2 },
      ]),
      run("r2", [
        { name: "test_divide", suite: "MathSuite", status: "failed", duration: 0.3 },
        { name: "test_subtract", suite: "MathSuite", status: "passed", duration: 0.2 },
      ]),
      run("r3", [
        { name: "test_divide", suite: "MathSuite", status: "passed", duration: 0.3 },
        { name: "test_subtract", suite: "MathSuite", status: "failed", duration: 0.2 },
      ]),
    ];
    const agg = aggregate(runs);
    expect(agg.flaky.map((f) => f.key)).toEqual([
      "MathSuite > test_divide",
      "MathSuite > test_subtract",
    ]);
    const divide = agg.flaky.find((f) => f.key === "MathSuite > test_divide")!;
    expect(divide.passed).toBe(2);
    expect(divide.failed).toBe(1);
  });
});
