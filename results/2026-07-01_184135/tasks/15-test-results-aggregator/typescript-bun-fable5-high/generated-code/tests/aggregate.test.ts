/**
 * TDD Cycle 3 — aggregation across matrix runs.
 *
 * Covers: per-status totals, duration summing, per-run breakdown, flaky
 * detection (passed in one run AND failed in another), and the distinction
 * between flaky tests and consistently failing tests.
 *
 * RED: failed with module-resolution error before src/aggregate.ts existed.
 */
import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregate";
import type { TestRun } from "../src/types";

/** Tiny fixture-builder so each test reads as data, not boilerplate. */
function run(source: string, cases: Array<[string, string, "passed" | "failed" | "skipped", number, string?]>): TestRun {
  return {
    source,
    cases: cases.map(([suite, name, status, durationSeconds, message]) => ({
      suite,
      name,
      status,
      durationSeconds,
      ...(message !== undefined ? { message } : {}),
    })),
  };
}

const SHARD1 = run("shard1.xml", [
  ["auth", "test_login", "passed", 0.5],
  ["auth", "test_flaky_network", "failed", 1.2, "connection reset"],
  ["auth", "test_skipped", "skipped", 0],
]);
const SHARD2 = run("shard2.xml", [
  ["auth", "test_login", "passed", 0.6],
  ["auth", "test_flaky_network", "passed", 1.0],
]);
const SHARD3 = run("shard3.json", [
  ["api", "test_delete", "failed", 0.7, "500 from server"],
]);

describe("aggregate", () => {
  test("computes overall totals across all runs", () => {
    const report = aggregate([SHARD1, SHARD2, SHARD3]);
    expect(report.totals).toEqual({
      total: 6,
      passed: 3,
      failed: 2,
      skipped: 1,
      durationSeconds: 4.0,
    });
  });

  test("keeps a per-run breakdown in input order", () => {
    const report = aggregate([SHARD1, SHARD2, SHARD3]);
    expect(report.perRun.map((r) => r.source)).toEqual(["shard1.xml", "shard2.xml", "shard3.json"]);
    expect(report.perRun[0]?.totals).toEqual({
      total: 3,
      passed: 1,
      failed: 1,
      skipped: 1,
      durationSeconds: 1.7,
    });
  });

  test("flags tests that both passed and failed as flaky", () => {
    const report = aggregate([SHARD1, SHARD2, SHARD3]);
    expect(report.flaky).toEqual([
      {
        id: "auth > test_flaky_network",
        passedIn: ["shard2.xml"],
        failedIn: ["shard1.xml"],
      },
    ]);
  });

  test("reports consistently failing tests as failed, not flaky", () => {
    const report = aggregate([SHARD1, SHARD2, SHARD3]);
    expect(report.failed).toEqual([
      { id: "api > test_delete", failedIn: ["shard3.json"], message: "500 from server" },
    ]);
  });

  test("a test that always passes is neither flaky nor failed", () => {
    const report = aggregate([SHARD1, SHARD2]);
    const ids = [...report.flaky, ...report.failed].map((t) => t.id);
    expect(ids).not.toContain("auth > test_login");
  });

  test("skipped-then-passed is not flaky", () => {
    const a = run("a.xml", [["s", "t", "skipped", 0]]);
    const b = run("b.xml", [["s", "t", "passed", 0.1]]);
    expect(aggregate([a, b]).flaky).toEqual([]);
  });

  test("throws a meaningful error when given no runs", () => {
    expect(() => aggregate([])).toThrow(/no test runs/i);
  });
});
