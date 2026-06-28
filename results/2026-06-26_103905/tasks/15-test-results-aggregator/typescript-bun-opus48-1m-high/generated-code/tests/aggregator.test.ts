import { describe, expect, it } from "bun:test";
import { aggregate } from "../src/aggregator.ts";
import type { TestRun } from "../src/types.ts";

/** Build a run quickly in tests. */
function run(name: string, cases: Array<[string, string, string, number?]>): TestRun {
  return {
    name,
    cases: cases.map(([suite, testName, status, duration]) => ({
      suite,
      name: testName,
      status: status as "passed" | "failed" | "skipped",
      duration: duration ?? 0,
    })),
  };
}

describe("aggregate totals", () => {
  it("sums passed/failed/skipped and duration across runs", () => {
    const runs: TestRun[] = [
      run("linux", [
        ["s", "a", "passed", 0.1],
        ["s", "b", "failed", 0.2],
      ]),
      run("mac", [
        ["s", "a", "passed", 0.15],
        ["s", "c", "skipped", 0],
      ]),
    ];

    const result = aggregate(runs);
    expect(result.totals.passed).toBe(2);
    expect(result.totals.failed).toBe(1);
    expect(result.totals.skipped).toBe(1);
    expect(result.totals.total).toBe(4);
    expect(result.totals.duration).toBeCloseTo(0.45);
    expect(result.runCount).toBe(2);
  });

  it("returns all-zero totals for no runs", () => {
    const result = aggregate([]);
    expect(result.totals).toEqual({
      passed: 0,
      failed: 0,
      skipped: 0,
      total: 0,
      duration: 0,
    });
    expect(result.flaky).toEqual([]);
    expect(result.runCount).toBe(0);
  });
});

describe("flaky detection", () => {
  it("flags a test that passed in one run and failed in another", () => {
    const runs: TestRun[] = [
      run("r1", [["auth", "login", "passed"]]),
      run("r2", [["auth", "login", "failed"]]),
      run("r3", [["auth", "login", "passed"]]),
    ];

    const result = aggregate(runs);
    expect(result.flaky).toHaveLength(1);
    expect(result.flaky[0]!.id).toBe("auth > login");
    expect(result.flaky[0]!.passed).toBe(2);
    expect(result.flaky[0]!.failed).toBe(1);
  });

  it("does NOT flag tests that are consistently passing or failing", () => {
    const runs: TestRun[] = [
      run("r1", [
        ["s", "always_pass", "passed"],
        ["s", "always_fail", "failed"],
      ]),
      run("r2", [
        ["s", "always_pass", "passed"],
        ["s", "always_fail", "failed"],
      ]),
    ];
    expect(aggregate(runs).flaky).toHaveLength(0);
  });

  it("ignores skipped outcomes when deciding flakiness", () => {
    // pass + skip is NOT flaky (no failure observed)
    const runs: TestRun[] = [
      run("r1", [["s", "t", "passed"]]),
      run("r2", [["s", "t", "skipped"]]),
    ];
    expect(aggregate(runs).flaky).toHaveLength(0);
  });

  it("uses the bare name as id when there is no suite", () => {
    const runs: TestRun[] = [
      run("r1", [["", "solo", "passed"]]),
      run("r2", [["", "solo", "failed"]]),
    ];
    expect(aggregate(runs).flaky[0]!.id).toBe("solo");
  });

  it("sorts flaky tests by failure count descending", () => {
    const runs: TestRun[] = [
      run("r1", [
        ["s", "rare", "passed"],
        ["s", "often", "failed"],
      ]),
      run("r2", [
        ["s", "rare", "failed"],
        ["s", "often", "failed"],
      ]),
      run("r3", [
        ["s", "rare", "passed"],
        ["s", "often", "passed"],
      ]),
    ];
    const flaky = aggregate(runs).flaky;
    expect(flaky.map((f) => f.id)).toEqual(["s > often", "s > rare"]);
  });
});
