import { describe, expect, test } from "bun:test";
import { createMockLicenseLookup } from "../src/licenseLookup";
import { formatReportMarkdown, formatReportText, generateReport } from "../src/report";
import type { LicenseConfig } from "../src/types";

// RED: fails until src/report.ts exports these.
const config: LicenseConfig = {
  allowlist: ["MIT"],
  denylist: ["GPL-3.0"],
};

const lookup = createMockLicenseLookup({
  "left-pad@1.3.0": "MIT",
  "old-gpl-lib@2.0.0": "GPL-3.0",
});

describe("generateReport", () => {
  test("builds a report entry + status for each dependency and totals the summary", async () => {
    const report = await generateReport(
      [
        { name: "left-pad", version: "1.3.0" },
        { name: "old-gpl-lib", version: "2.0.0" },
        { name: "mystery-pkg", version: "0.1.0" },
      ],
      lookup,
      config,
    );

    expect(report.entries).toEqual([
      { name: "left-pad", version: "1.3.0", license: "MIT", status: "approved" },
      { name: "old-gpl-lib", version: "2.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery-pkg", version: "0.1.0", license: null, status: "unknown" },
    ]);
    expect(report.summary).toEqual({ total: 3, approved: 1, denied: 1, unknown: 1 });
  });

  test("returns an empty report for no dependencies", async () => {
    const report = await generateReport([], lookup, config);

    expect(report.entries).toEqual([]);
    expect(report.summary).toEqual({ total: 0, approved: 0, denied: 0, unknown: 0 });
  });
});

describe("formatReportText", () => {
  test("renders one bracketed line per entry plus a machine-parseable summary line", async () => {
    const report = await generateReport(
      [
        { name: "left-pad", version: "1.3.0" },
        { name: "old-gpl-lib", version: "2.0.0" },
        { name: "mystery-pkg", version: "0.1.0" },
      ],
      lookup,
      config,
    );

    const text = formatReportText(report);

    expect(text).toContain("[APPROVED] left-pad@1.3.0 - MIT");
    expect(text).toContain("[DENIED] old-gpl-lib@2.0.0 - GPL-3.0");
    expect(text).toContain("[UNKNOWN] mystery-pkg@0.1.0 - UNKNOWN");
    expect(text).toContain("SUMMARY: total=3 approved=1 denied=1 unknown=1");
  });
});

describe("formatReportMarkdown", () => {
  test("renders a markdown table with a summary line", async () => {
    const report = await generateReport(
      [{ name: "left-pad", version: "1.3.0" }],
      lookup,
      config,
    );

    const markdown = formatReportMarkdown(report);

    expect(markdown).toContain("| Dependency | Version | License | Status |");
    expect(markdown).toContain("| left-pad | 1.3.0 | MIT | approved |");
    expect(markdown).toContain("**Summary:** total=1, approved=1, denied=0, unknown=0");
  });
});
