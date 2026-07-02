// TDD step 4: report formatting (human-readable text + machine-readable JSON).
import { describe, expect, test } from "bun:test";
import { formatReportText, formatReportJson } from "../src/report";
import type { ComplianceReport } from "../src/types";

const report: ComplianceReport = {
  results: [
    { name: "chalk", version: "4.1.0", license: "MIT", status: "approved" },
    { name: "gpl-lib", version: "1.0.0", license: "GPL-3.0", status: "denied" },
    { name: "mystery-pkg", version: "1.0.0", license: null, status: "unknown" },
  ],
  summary: { total: 3, approved: 1, denied: 1, unknown: 1 },
};

describe("formatReportText", () => {
  test("lists every dependency with its status and license", () => {
    const text = formatReportText(report);

    expect(text).toContain("chalk@4.1.0");
    expect(text).toContain("MIT");
    expect(text).toContain("APPROVED");

    expect(text).toContain("gpl-lib@1.0.0");
    expect(text).toContain("GPL-3.0");
    expect(text).toContain("DENIED");

    expect(text).toContain("mystery-pkg@1.0.0");
    expect(text).toContain("UNKNOWN");
  });

  test("includes an accurate summary line", () => {
    const text = formatReportText(report);
    expect(text).toContain("Total: 3");
    expect(text).toContain("Approved: 1");
    expect(text).toContain("Denied: 1");
    expect(text).toContain("Unknown: 1");
  });
});

describe("formatReportJson", () => {
  test("round-trips the report as valid JSON", () => {
    const json = formatReportJson(report);
    expect(JSON.parse(json)).toEqual(report);
  });
});
