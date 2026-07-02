/**
 * TDD Cycle 4 — markdown summary generation (GitHub Actions job summary).
 *
 * RED: failed with module-resolution error before src/markdown.ts existed.
 */
import { describe, expect, test } from "bun:test";
import { renderMarkdownSummary } from "../src/markdown";
import type { AggregateReport } from "../src/types";

const REPORT: AggregateReport = {
  totals: { total: 10, passed: 6, failed: 2, skipped: 2, durationSeconds: 4.9 },
  perRun: [
    { source: "shard1.xml", totals: { total: 4, passed: 2, failed: 1, skipped: 1, durationSeconds: 2.0 } },
    { source: "shard2.xml", totals: { total: 4, passed: 3, failed: 0, skipped: 1, durationSeconds: 2.0 } },
    { source: "shard3.json", totals: { total: 2, passed: 1, failed: 1, skipped: 0, durationSeconds: 0.9 } },
  ],
  flaky: [{ id: "auth > test_flaky_network", passedIn: ["shard2.xml"], failedIn: ["shard1.xml"] }],
  failed: [{ id: "api > test_delete", failedIn: ["shard3.json"], message: "500 from server" }],
};

const ALL_GREEN: AggregateReport = {
  totals: { total: 5, passed: 5, failed: 0, skipped: 0, durationSeconds: 1.5 },
  perRun: [{ source: "ok.xml", totals: { total: 5, passed: 5, failed: 0, skipped: 0, durationSeconds: 1.5 } }],
  flaky: [],
  failed: [],
};

describe("renderMarkdownSummary", () => {
  test("includes a totals table with exact counts and duration", () => {
    const md = renderMarkdownSummary(REPORT);
    expect(md).toContain("# 🧪 Test Results");
    expect(md).toContain("| ✅ Passed | 6 |");
    expect(md).toContain("| ❌ Failed | 2 |");
    expect(md).toContain("| ⏭️ Skipped | 2 |");
    expect(md).toContain("| **Total** | **10** |");
    expect(md).toContain("**Total duration:** 4.90s across 3 runs");
  });

  test("lists flaky tests with the runs they passed and failed in", () => {
    const md = renderMarkdownSummary(REPORT);
    expect(md).toContain("## ⚠️ Flaky tests (1)");
    expect(md).toContain("| `auth > test_flaky_network` | shard2.xml | shard1.xml |");
  });

  test("lists consistently failing tests with their message", () => {
    const md = renderMarkdownSummary(REPORT);
    expect(md).toContain("## ❌ Failing tests (1)");
    expect(md).toContain("| `api > test_delete` | shard3.json | 500 from server |");
  });

  test("includes a per-run breakdown row per source file", () => {
    const md = renderMarkdownSummary(REPORT);
    expect(md).toContain("| shard1.xml | 4 | 2 | 1 | 1 | 2.00s |");
    expect(md).toContain("| shard3.json | 2 | 1 | 1 | 0 | 0.90s |");
  });

  test("celebrates a fully green build and omits empty sections", () => {
    const md = renderMarkdownSummary(ALL_GREEN);
    expect(md).toContain("✅ All 5 tests passed.");
    expect(md).toContain("No flaky tests detected.");
    expect(md).not.toContain("## ❌ Failing tests");
    expect(md).not.toContain("## ⚠️ Flaky tests");
  });

  test("escapes pipe characters in test ids so tables stay intact", () => {
    const md = renderMarkdownSummary({
      ...ALL_GREEN,
      failed: [{ id: "a | b > t", failedIn: ["x.xml"] }],
      totals: { ...ALL_GREEN.totals, failed: 1 },
    });
    expect(md).toContain("a \\| b > t");
  });
});
