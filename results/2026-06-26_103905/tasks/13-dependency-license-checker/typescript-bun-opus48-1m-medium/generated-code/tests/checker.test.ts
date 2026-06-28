import { describe, expect, test } from "bun:test";
import { classifyLicense, generateReport } from "../src/checker.ts";
import type { Dependency, LicenseConfig, LicenseLookup } from "../src/types.ts";

const config: LicenseConfig = {
  allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
  deny: ["GPL-3.0", "AGPL-3.0"],
};

describe("classifyLicense", () => {
  test("returns 'approved' for an allow-listed license", () => {
    expect(classifyLicense("MIT", config)).toBe("approved");
  });

  test("returns 'denied' for a deny-listed license", () => {
    expect(classifyLicense("GPL-3.0", config)).toBe("denied");
  });

  test("returns 'unknown' for a license on neither list", () => {
    expect(classifyLicense("WTFPL", config)).toBe("unknown");
  });

  test("returns 'unknown' when the license is null", () => {
    expect(classifyLicense(null, config)).toBe("unknown");
  });

  test("deny-list takes precedence over allow-list", () => {
    const conflicting: LicenseConfig = { allow: ["MIT"], deny: ["MIT"] };
    expect(classifyLicense("MIT", conflicting)).toBe("denied");
  });

  test("matching is case-insensitive", () => {
    expect(classifyLicense("mit", config)).toBe("approved");
  });
});

describe("generateReport", () => {
  // A mock license lookup keyed by dependency name — stands in for a
  // real registry query so the report logic is deterministic in tests.
  const mockDb: Record<string, string | null> = {
    lodash: "MIT",
    "evil-lib": "GPL-3.0",
    "mystery-pkg": null,
  };
  const lookup: LicenseLookup = (dep: Dependency) =>
    dep.name in mockDb ? mockDb[dep.name] : undefined;

  test("classifies each dependency and summarizes the results", () => {
    const deps: Dependency[] = [
      { name: "lodash", version: "4.17.21" },
      { name: "evil-lib", version: "1.0.0" },
      { name: "mystery-pkg", version: "2.0.0" },
      { name: "ghost-pkg", version: "0.0.1" },
    ];

    const report = generateReport(deps, lookup, config);

    expect(report.entries).toEqual([
      { name: "lodash", version: "4.17.21", license: "MIT", status: "approved" },
      { name: "evil-lib", version: "1.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery-pkg", version: "2.0.0", license: null, status: "unknown" },
      { name: "ghost-pkg", version: "0.0.1", license: null, status: "unknown" },
    ]);

    expect(report.summary).toEqual({
      total: 4,
      approved: 1,
      denied: 1,
      unknown: 2,
      compliant: false,
    });
  });

  test("reports compliant=true when all dependencies are approved", () => {
    const deps: Dependency[] = [{ name: "lodash", version: "4.17.21" }];
    const report = generateReport(deps, lookup, config);
    expect(report.summary.compliant).toBe(true);
  });

  test("handles an empty dependency list", () => {
    const report = generateReport([], lookup, config);
    expect(report.summary).toEqual({
      total: 0,
      approved: 0,
      denied: 0,
      unknown: 0,
      compliant: true,
    });
  });
});
