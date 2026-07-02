/**
 * TDD cycle 4 (RED): markdown summary for a GitHub Actions job summary.
 *
 * The summary must contain a totals table, an overall status line, and a
 * flaky-tests section that only appears when flaky tests exist.
 */
import { describe, expect, test } from "bun:test";
import { renderMarkdownSummary } from "../src/markdown";
import type { AggregateSummary } from "../src/types";

const BASE: AggregateSummary = {
  total: 12,
  passed: 8,
  failed: 2,
  skipped: 2,
  durationSec: 12.345,
  files: 3,
  flaky: [{ id: "net :: retry", passes: 2, failures: 1 }],
};

describe("renderMarkdownSummary", () => {
  test("renders header, status and totals table", () => {
    const md = renderMarkdownSummary(BASE);
    expect(md).toContain("# 🧪 Test Results Summary");
    expect(md).toContain("**Status:** ❌ 2 test(s) failed");
    expect(md).toContain("| Total tests | 12 |");
    expect(md).toContain("| ✅ Passed | 8 |");
    expect(md).toContain("| ❌ Failed | 2 |");
    expect(md).toContain("| ⏭️ Skipped | 2 |");
    // duration rounded to 2 decimals
    expect(md).toContain("| ⏱️ Duration | 12.35s |");
    expect(md).toContain("| 📄 Result files | 3 |");
  });

  test("renders a flaky-tests table when flaky tests exist", () => {
    const md = renderMarkdownSummary(BASE);
    expect(md).toContain("## ⚠️ Flaky tests (1)");
    expect(md).toContain("| `net :: retry` | 2 | 1 |");
  });

  test("omits flaky section and reports success when everything passed", () => {
    const md = renderMarkdownSummary({
      ...BASE,
      failed: 0,
      skipped: 0,
      passed: 12,
      flaky: [],
    });
    expect(md).toContain("**Status:** ✅ All tests passed");
    expect(md).not.toContain("Flaky tests");
  });

  test("handles the zero-tests edge case", () => {
    const md = renderMarkdownSummary({
      total: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      durationSec: 0,
      files: 0,
      flaky: [],
    });
    expect(md).toContain("**Status:** ⚠️ No test results found");
  });
});
