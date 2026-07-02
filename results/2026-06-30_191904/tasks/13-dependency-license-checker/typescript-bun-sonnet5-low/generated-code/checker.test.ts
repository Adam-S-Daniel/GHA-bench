import { describe, expect, test } from "bun:test";
import { generateComplianceReport } from "./checker";
import type { Dependency, LicenseConfig, LicenseLookup } from "./types";

describe("generateComplianceReport", () => {
  const config: LicenseConfig = {
    allowList: ["MIT", "Apache-2.0"],
    denyList: ["GPL-3.0"],
  };

  test("marks a dependency approved when its license is in the allow-list", async () => {
    const deps: Dependency[] = [{ name: "lodash", version: "4.17.21" }];
    const mockLookup: LicenseLookup = async () => "MIT";

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.entries).toEqual([
      { name: "lodash", version: "4.17.21", license: "MIT", status: "approved" },
    ]);
    expect(report.summary).toEqual({ total: 1, approved: 1, denied: 0, unknown: 0 });
  });

  test("marks a dependency denied when its license is in the deny-list", async () => {
    const deps: Dependency[] = [{ name: "badlib", version: "1.0.0" }];
    const mockLookup: LicenseLookup = async () => "GPL-3.0";

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.entries[0]).toEqual({
      name: "badlib",
      version: "1.0.0",
      license: "GPL-3.0",
      status: "denied",
    });
  });

  test("marks a dependency unknown when the license is not on either list", async () => {
    const deps: Dependency[] = [{ name: "obscurelib", version: "0.1.0" }];
    const mockLookup: LicenseLookup = async () => "WTFPL";

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.entries[0].status).toBe("unknown");
  });

  test("marks a dependency unknown when the license lookup returns null", async () => {
    const deps: Dependency[] = [{ name: "nolicenselib", version: "2.0.0" }];
    const mockLookup: LicenseLookup = async () => null;

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.entries[0]).toEqual({
      name: "nolicenselib",
      version: "2.0.0",
      license: null,
      status: "unknown",
    });
  });

  test("computes an aggregate summary across multiple dependencies", async () => {
    const deps: Dependency[] = [
      { name: "a", version: "1.0.0" },
      { name: "b", version: "1.0.0" },
      { name: "c", version: "1.0.0" },
      { name: "d", version: "1.0.0" },
    ];
    const licenses: Record<string, string | null> = {
      a: "MIT",
      b: "GPL-3.0",
      c: "SomeUnknownLicense",
      d: null as unknown as string,
    };
    const mockLookup: LicenseLookup = async (dep) => licenses[dep.name] ?? null;

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.summary).toEqual({ total: 4, approved: 1, denied: 1, unknown: 2 });
  });

  test("license comparison is case-insensitive", async () => {
    const deps: Dependency[] = [{ name: "lib", version: "1.0.0" }];
    const mockLookup: LicenseLookup = async () => "mit";

    const report = await generateComplianceReport(deps, config, mockLookup);

    expect(report.entries[0].status).toBe("approved");
  });

  test("propagates a meaningful error if lookup throws", async () => {
    const deps: Dependency[] = [{ name: "brokenlib", version: "1.0.0" }];
    const mockLookup: LicenseLookup = async () => {
      throw new Error("network failure");
    };

    await expect(generateComplianceReport(deps, config, mockLookup)).rejects.toThrow(
      /brokenlib.*network failure/i
    );
  });
});
