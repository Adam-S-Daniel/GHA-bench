// RED/GREEN cycle 3: compliance report generation and formatting.
// The license lookup is INJECTED (LicenseLookup function type), so these
// tests mock it with an in-memory map — no network / registry access.
import { describe, expect, test } from "bun:test";
import { formatReport, generateReport } from "../src/report";
import type { Dependency, LicenseConfig, LicenseLookup } from "../src/types";

const config: LicenseConfig = {
  allow: ["MIT", "Apache-2.0"],
  deny: ["GPL-3.0-only"],
};

// Mock lookup: fixed map instead of a real registry query.
const mockDb: Record<string, string> = {
  "left-pad": "MIT",
  "evil-lib": "GPL-3.0-only",
};
const mockLookup: LicenseLookup = (dep) => mockDb[dep.name];

const deps: Dependency[] = [
  { name: "left-pad", version: "^1.3.0" },
  { name: "evil-lib", version: "2.0.0" },
  { name: "mystery-pkg", version: "0.1.0" },
];

describe("generateReport", () => {
  test("classifies each dependency using the injected lookup", () => {
    const report = generateReport(deps, config, mockLookup);
    expect(report.entries).toEqual([
      { name: "left-pad", version: "^1.3.0", license: "MIT", status: "approved" },
      { name: "evil-lib", version: "2.0.0", license: "GPL-3.0-only", status: "denied" },
      { name: "mystery-pkg", version: "0.1.0", license: undefined, status: "unknown" },
    ]);
  });

  test("computes summary counts", () => {
    const report = generateReport(deps, config, mockLookup);
    expect(report.summary).toEqual({
      total: 3,
      approved: 1,
      denied: 1,
      unknown: 1,
    });
  });

  test("produces an empty report for zero dependencies", () => {
    const report = generateReport([], config, mockLookup);
    expect(report.entries).toEqual([]);
    expect(report.summary).toEqual({ total: 0, approved: 0, denied: 0, unknown: 0 });
  });
});

describe("formatReport", () => {
  test("renders the exact human-readable report text", () => {
    const report = generateReport(deps, config, mockLookup);
    expect(formatReport(report)).toBe(
      [
        "Dependency License Compliance Report",
        "====================================",
        "APPROVED left-pad@^1.3.0 MIT",
        "DENIED evil-lib@2.0.0 GPL-3.0-only",
        "UNKNOWN mystery-pkg@0.1.0 (license not found)",
        "------------------------------------",
        "Summary: total=3 approved=1 denied=1 unknown=1",
      ].join("\n"),
    );
  });
});
