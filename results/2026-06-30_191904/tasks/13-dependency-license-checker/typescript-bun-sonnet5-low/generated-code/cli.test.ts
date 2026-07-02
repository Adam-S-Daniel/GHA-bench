import { describe, expect, test } from "bun:test";
import { loadLicenseConfig, resolveExitCode } from "./cli";
import type { ComplianceReport } from "./types";

describe("loadLicenseConfig", () => {
  test("parses a valid config JSON string", () => {
    const config = loadLicenseConfig(
      JSON.stringify({ allowList: ["MIT"], denyList: ["GPL-3.0"] })
    );
    expect(config).toEqual({ allowList: ["MIT"], denyList: ["GPL-3.0"] });
  });

  test("throws a meaningful error when allowList/denyList are missing", () => {
    expect(() => loadLicenseConfig(JSON.stringify({}))).toThrow(/allowList/i);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => loadLicenseConfig("not json")).toThrow(/invalid JSON/i);
  });
});

describe("resolveExitCode", () => {
  test("returns 0 when there are no denied dependencies", () => {
    const report: ComplianceReport = {
      entries: [],
      summary: { total: 0, approved: 0, denied: 0, unknown: 0 },
    };
    expect(resolveExitCode(report)).toBe(0);
  });

  test("returns 1 when at least one dependency is denied", () => {
    const report: ComplianceReport = {
      entries: [],
      summary: { total: 1, approved: 0, denied: 1, unknown: 0 },
    };
    expect(resolveExitCode(report)).toBe(1);
  });
});
