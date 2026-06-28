import { describe, expect, test } from "bun:test";
import { createDbLookup, formatReport } from "../src/report.ts";
import type { ComplianceReport, Dependency } from "../src/types.ts";

describe("createDbLookup", () => {
  // The DB-backed lookup is the "mock" stand-in for a real registry query:
  // it resolves licenses from an in-memory map loaded from a JSON file.
  const lookup = createDbLookup({ lodash: "MIT", "evil-lib": "GPL-3.0" });

  test("returns the mapped license for a known package", () => {
    const dep: Dependency = { name: "lodash", version: "4.17.21" };
    expect(lookup(dep)).toBe("MIT");
  });

  test("returns undefined for a package not in the database", () => {
    const dep: Dependency = { name: "unknown-pkg", version: "1.0.0" };
    expect(lookup(dep)).toBeUndefined();
  });
});

describe("formatReport", () => {
  const report: ComplianceReport = {
    entries: [
      { name: "lodash", version: "4.17.21", license: "MIT", status: "approved" },
      { name: "evil-lib", version: "1.0.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery", version: "2.0.0", license: null, status: "unknown" },
    ],
    summary: { total: 3, approved: 1, denied: 1, unknown: 1, compliant: false },
  };

  test("text format includes a line per dependency with its status", () => {
    const out = formatReport(report, "text");
    expect(out).toContain("lodash@4.17.21");
    expect(out).toContain("MIT");
    expect(out).toContain("APPROVED");
    expect(out).toContain("evil-lib@1.0.0");
    expect(out).toContain("DENIED");
    expect(out).toContain("mystery@2.0.0");
    expect(out).toContain("UNKNOWN");
  });

  test("text format includes a summary line and a NOT COMPLIANT verdict", () => {
    const out = formatReport(report, "text");
    expect(out).toContain("Total: 3");
    expect(out).toContain("Approved: 1");
    expect(out).toContain("Denied: 1");
    expect(out).toContain("Unknown: 1");
    expect(out).toContain("NOT COMPLIANT");
  });

  test("json format round-trips to the original report object", () => {
    const out = formatReport(report, "json");
    expect(JSON.parse(out)).toEqual(report);
  });
});
