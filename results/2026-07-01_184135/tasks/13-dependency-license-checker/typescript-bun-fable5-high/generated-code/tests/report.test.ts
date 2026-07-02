/**
 * Tests for report rendering (RED first: src/report.ts does not exist).
 *
 * Approach: formatReport() renders a ComplianceReport as deterministic plain
 * text — one "name@version: license [status]" line per dependency plus a
 * summary line — so CI logs can be asserted on exactly.
 */
import { describe, expect, test } from "bun:test";
import { formatReport } from "../src/report";
import type { ComplianceReport } from "../src/types";

const report: ComplianceReport = {
  entries: [
    { name: "left-pad", version: "1.3.0", license: "GPL-3.0", status: "denied" },
    { name: "mystery-lib", version: "0.0.1", license: null, status: "unknown" },
    { name: "react", version: "18.2.0", license: "MIT", status: "approved" },
  ],
  summary: { approved: 1, denied: 1, unknown: 1 },
};

describe("formatReport", () => {
  test("renders one line per dependency plus a summary line", () => {
    expect(formatReport(report)).toBe(
      [
        "License Compliance Report",
        "=========================",
        "left-pad@1.3.0: GPL-3.0 [denied]",
        "mystery-lib@0.0.1: UNKNOWN [unknown]",
        "react@18.2.0: MIT [approved]",
        "Summary: 1 approved, 1 denied, 1 unknown",
      ].join("\n"),
    );
  });

  test("renders an explicit notice for an empty dependency list", () => {
    const empty: ComplianceReport = {
      entries: [],
      summary: { approved: 0, denied: 0, unknown: 0 },
    };
    expect(formatReport(empty)).toContain("No dependencies found.");
    expect(formatReport(empty)).toContain("Summary: 0 approved, 0 denied, 0 unknown");
  });
});
