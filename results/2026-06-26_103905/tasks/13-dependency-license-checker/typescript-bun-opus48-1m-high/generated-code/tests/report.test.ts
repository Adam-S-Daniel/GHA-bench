/**
 * Tests for report generation and formatting.
 *
 * generateReport() ties parsing-output + lookup + policy together into a
 * ComplianceReport. formatReport() renders it to a stable, human-readable
 * string whose exact lines the CI workflow can assert on.
 */
import { describe, expect, it } from "bun:test";
import { formatReport, generateReport } from "../src/report.ts";
import { createDatabaseLookup } from "../src/lookup.ts";
import type { Dependency, LicensePolicy } from "../src/types.ts";

const deps: Dependency[] = [
  { name: "left-pad", version: "1.3.0" },
  { name: "evil-pkg", version: "2.0.0" },
  { name: "mystery", version: "0.0.1" },
];

const lookup = createDatabaseLookup({
  "left-pad@1.3.0": "MIT",
  "evil-pkg@2.0.0": "GPL-3.0",
});

const policy: LicensePolicy = {
  allow: ["MIT", "Apache-2.0"],
  deny: ["GPL-3.0"],
};

describe("generateReport", () => {
  it("classifies every dependency and computes a summary", () => {
    const report = generateReport(deps, lookup, policy);

    expect(report.entries).toEqual([
      { name: "left-pad", version: "1.3.0", license: "MIT", status: "approved" },
      { name: "evil-pkg", version: "2.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery", version: "0.0.1", license: null, status: "unknown" },
    ]);

    expect(report.summary).toEqual({
      total: 3,
      approved: 1,
      denied: 1,
      unknown: 1,
    });
  });

  it("is non-compliant when any dependency is denied", () => {
    expect(generateReport(deps, lookup, policy).compliant).toBe(false);
  });

  it("is compliant when all dependencies are approved", () => {
    const okDeps: Dependency[] = [{ name: "left-pad", version: "1.3.0" }];
    expect(generateReport(okDeps, lookup, policy).compliant).toBe(true);
  });

  it("treats unknown as a failure only when failOnUnknown is set", () => {
    const unknownDep: Dependency[] = [{ name: "mystery", version: "0.0.1" }];
    expect(generateReport(unknownDep, lookup, policy).compliant).toBe(true);

    const strict: LicensePolicy = { ...policy, failOnUnknown: true };
    expect(generateReport(unknownDep, lookup, strict).compliant).toBe(false);
  });
});

describe("formatReport", () => {
  it("renders a table, a summary line, and a RESULT line", () => {
    const report = generateReport(deps, lookup, policy);
    const text = formatReport(report);

    // Spot-check exact, assertable lines (these are what CI greps for).
    expect(text).toContain("left-pad@1.3.0");
    expect(text).toContain("MIT");
    expect(text).toContain("APPROVED");
    expect(text).toContain("evil-pkg@2.0.0");
    expect(text).toContain("DENIED");
    expect(text).toContain("mystery@0.0.1");
    expect(text).toContain("UNKNOWN");
    expect(text).toContain("Summary: 1 approved, 1 denied, 1 unknown (3 total)");
    expect(text).toContain("RESULT: FAIL");
  });

  it("renders RESULT: PASS when compliant", () => {
    const okDeps: Dependency[] = [{ name: "left-pad", version: "1.3.0" }];
    const text = formatReport(generateReport(okDeps, lookup, policy));
    expect(text).toContain("RESULT: PASS");
  });
});
