/**
 * TDD cycle 3 (RED): aggregation across matrix runs.
 *
 * - totals: passed / failed / skipped counts and summed duration
 * - flaky detection: same "suite :: name" passed in >=1 run AND failed in >=1
 *   run (skips are neutral and never make a test flaky)
 */
import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregate";
import type { TestFileResult } from "../src/types";

/** Small builder to keep fixtures readable. */
function run(
  source: string,
  cases: Array<[suite: string, name: string, status: "passed" | "failed" | "skipped", dur: number]>,
): TestFileResult {
  return {
    source,
    cases: cases.map(([suite, name, status, durationSec]) => ({
      suite,
      name,
      status,
      durationSec,
    })),
  };
}

describe("aggregate", () => {
  test("computes totals across multiple files", () => {
    const summary = aggregate([
      run("shard1.xml", [
        ["auth", "login", "passed", 1.0],
        ["auth", "logout", "failed", 0.5],
      ]),
      run("shard2.json", [
        ["cart", "add", "passed", 0.25],
        ["cart", "remove", "skipped", 0],
      ]),
    ]);
    expect(summary.total).toBe(4);
    expect(summary.passed).toBe(2);
    expect(summary.failed).toBe(1);
    expect(summary.skipped).toBe(1);
    expect(summary.durationSec).toBeCloseTo(1.75);
    expect(summary.files).toBe(2);
  });

  test("flags tests that pass in one run and fail in another as flaky", () => {
    const summary = aggregate([
      run("os-linux.xml", [["net", "retry", "passed", 1]]),
      run("os-mac.xml", [["net", "retry", "failed", 1]]),
      run("os-win.xml", [["net", "retry", "passed", 1]]),
    ]);
    expect(summary.flaky).toEqual([
      { id: "net :: retry", passes: 2, failures: 1 },
    ]);
  });

  test("consistently failing or skipped tests are not flaky", () => {
    const summary = aggregate([
      run("a.xml", [
        ["s", "always-fails", "failed", 1],
        ["s", "sometimes-skipped", "skipped", 0],
      ]),
      run("b.xml", [
        ["s", "always-fails", "failed", 1],
        ["s", "sometimes-skipped", "passed", 1],
      ]),
    ]);
    expect(summary.flaky).toEqual([]);
  });

  test("flaky list is sorted by id for stable output", () => {
    const summary = aggregate([
      run("a.xml", [
        ["z", "zz", "passed", 0],
        ["a", "aa", "passed", 0],
      ]),
      run("b.xml", [
        ["z", "zz", "failed", 0],
        ["a", "aa", "failed", 0],
      ]),
    ]);
    expect(summary.flaky.map((f) => f.id)).toEqual(["a :: aa", "z :: zz"]);
  });

  test("handles the empty input edge case", () => {
    const summary = aggregate([]);
    expect(summary).toEqual({
      total: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      durationSec: 0,
      files: 0,
      flaky: [],
    });
  });
});
