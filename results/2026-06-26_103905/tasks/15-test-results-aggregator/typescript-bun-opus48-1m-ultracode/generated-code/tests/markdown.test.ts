/**
 * Tests for the markdown renderer that produces the GitHub Actions job summary.
 * We assert on exact, stable strings so the act-driven integration tests can
 * grep the same output with confidence.
 */
import { describe, expect, test } from "bun:test";
import { aggregate } from "../src/aggregate";
import { formatDuration, renderMarkdown } from "../src/markdown";
import type { TestRun } from "../src/types";

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

describe("formatDuration", () => {
  test("renders seconds with three decimals and a unit", () => {
    expect(formatDuration(0.7)).toBe("0.700s");
    expect(formatDuration(12)).toBe("12.000s");
    expect(formatDuration(0)).toBe("0.000s");
  });
});

describe("renderMarkdown", () => {
  const failing = aggregate([
    run("linux.json", "linux", [
      ["Math", "adds", "passed", 0.1],
      ["Net", "fetches", "passed", 0.1],
      ["Math", "divides", "failed", 0.2],
      ["Math", "todo", "skipped", 0],
    ]),
    run("windows.xml", "windows", [
      ["Math", "adds", "passed", 0.15],
      ["Net", "fetches", "failed", 0.1],
      ["Math", "divides", "failed", 0.25],
    ]),
  ]);

  test("includes a heading and an overall FAILED status", () => {
    const md = renderMarkdown(failing);
    expect(md).toContain("## Test Results Summary");
    expect(md).toContain("**Result:** FAILED");
  });

  test("renders a totals table with exact counts and duration", () => {
    const md = renderMarkdown(failing);
    // linux: 2P/1F/1S (0.400s); windows: 1P/2F/0S (0.500s).
    // => 3 passed, 3 failed, 1 skipped, 7 total, 0.900s duration.
    expect(md).toContain("| Passed | 3 |");
    expect(md).toContain("| Failed | 3 |");
    expect(md).toContain("| Skipped | 1 |");
    expect(md).toContain("| Total | 7 |");
    expect(md).toContain("| Duration | 0.900s |");
  });

  test("renders a flaky-tests section listing the flaky test", () => {
    const md = renderMarkdown(failing);
    expect(md).toContain("### Flaky Tests (1)");
    // Net::fetches passed once, failed once, across 2 runs.
    expect(md).toContain("| Net::fetches | 1 | 1 | 2 |");
  });

  test("renders a per-run breakdown row for each run", () => {
    const md = renderMarkdown(failing);
    expect(md).toContain("### Per-Run Breakdown");
    expect(md).toContain("| linux | 2 | 1 | 1 | 0.400s |");
    expect(md).toContain("| windows | 1 | 2 | 0 | 0.500s |");
  });

  test("reports a clean PASSED summary with no flaky section table", () => {
    const green = aggregate([
      run("a.json", "a", [["S", "x", "passed", 0.1]]),
      run("b.json", "b", [["S", "x", "passed", 0.2]]),
    ]);
    const md = renderMarkdown(green);
    expect(md).toContain("**Result:** PASSED");
    expect(md).toContain("No flaky tests detected.");
    expect(md).not.toContain("### Flaky Tests (");
  });
});
