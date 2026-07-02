/**
 * TDD Cycle 5 — file discovery + end-to-end orchestration (the CLI's core).
 *
 * The exact machine-readable AGGREGATE_RESULT line is load-bearing: the act
 * test harness greps for it in workflow logs and asserts exact values, so we
 * pin its format here.
 *
 * RED: failed with module-resolution error before src/cli.ts existed.
 */
import { describe, expect, test } from "bun:test";
import { aggregateDirectory, discoverResultFiles, machineLine } from "../src/cli";

const CASE1 = new URL("../fixtures/case1", import.meta.url).pathname;
const CASE2 = new URL("../fixtures/case2", import.meta.url).pathname;

describe("discoverResultFiles", () => {
  test("finds .xml and .json files sorted by name, ignoring other extensions", async () => {
    const files = await discoverResultFiles(CASE1);
    expect(files.map((f) => f.split("/").pop())).toEqual([
      "json-shard-windows.json",
      "junit-shard-macos.xml",
      "junit-shard-ubuntu.xml",
    ]);
  });

  test("throws a meaningful error for a missing directory", async () => {
    expect(discoverResultFiles("/nonexistent/results")).rejects.toThrow(
      /\/nonexistent\/results.*not.*(exist|directory)/i,
    );
  });

  test("throws a meaningful error when no result files are present", async () => {
    const empty = `${import.meta.dir}/tmp-empty-${process.pid}`;
    const { mkdir, rmdir } = await import("node:fs/promises");
    await mkdir(empty, { recursive: true });
    try {
      expect(discoverResultFiles(empty)).rejects.toThrow(/no .*\.xml.*\.json.*files/i);
    } finally {
      await rmdir(empty);
    }
  });
});

describe("aggregateDirectory (end to end on fixtures)", () => {
  test("case1: mixed matrix run with one flaky and one real failure", async () => {
    const report = await aggregateDirectory(CASE1);
    expect(report.totals).toEqual({
      total: 10,
      passed: 6,
      failed: 2,
      skipped: 2,
      durationSeconds: 4.9,
    });
    expect(report.flaky.map((t) => t.id)).toEqual(["auth > test_flaky_network"]);
    expect(report.failed.map((t) => t.id)).toEqual(["api > test_delete"]);
  });

  test("case2: all-green matrix run", async () => {
    const report = await aggregateDirectory(CASE2);
    expect(report.totals).toEqual({
      total: 5,
      passed: 5,
      failed: 0,
      skipped: 0,
      durationSeconds: 1.5,
    });
    expect(report.flaky).toEqual([]);
    expect(report.failed).toEqual([]);
  });
});

describe("machineLine", () => {
  test("formats the exact greppable line the act harness asserts on", async () => {
    const report = await aggregateDirectory(CASE1);
    expect(machineLine(report)).toBe(
      "AGGREGATE_RESULT total=10 passed=6 failed=2 skipped=2 duration=4.90s flaky=1",
    );
  });

  test("all-green line", async () => {
    const report = await aggregateDirectory(CASE2);
    expect(machineLine(report)).toBe(
      "AGGREGATE_RESULT total=5 passed=5 failed=0 skipped=0 duration=1.50s flaky=0",
    );
  });
});
