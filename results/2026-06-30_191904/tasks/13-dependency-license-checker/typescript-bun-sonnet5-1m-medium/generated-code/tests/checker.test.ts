// TDD step 3: compliance checking against an allow/deny license policy.
import { describe, expect, test } from "bun:test";
import { checkCompliance } from "../src/checker";
import { InMemoryLicenseLookup } from "../src/licenseLookup";
import type { LicensePolicy } from "../src/types";

const policy: LicensePolicy = {
  allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
  deny: ["GPL-3.0", "AGPL-3.0"],
};

describe("checkCompliance", () => {
  test("marks a license on the allow-list as approved", async () => {
    const lookup = new InMemoryLicenseLookup({ chalk: "MIT" });
    const report = await checkCompliance([{ name: "chalk", version: "4.1.0" }], lookup, policy);

    expect(report.results).toEqual([
      { name: "chalk", version: "4.1.0", license: "MIT", status: "approved" },
    ]);
    expect(report.summary).toEqual({ total: 1, approved: 1, denied: 0, unknown: 0 });
  });

  test("marks a license on the deny-list as denied", async () => {
    const lookup = new InMemoryLicenseLookup({ "gpl-lib": "GPL-3.0" });
    const report = await checkCompliance([{ name: "gpl-lib", version: "1.0.0" }], lookup, policy);

    expect(report.results[0]).toEqual({
      name: "gpl-lib",
      version: "1.0.0",
      license: "GPL-3.0",
      status: "denied",
    });
    expect(report.summary.denied).toBe(1);
  });

  test("marks a license absent from both lists as unknown", async () => {
    const lookup = new InMemoryLicenseLookup({ "left-pad": "WTFPL" });
    const report = await checkCompliance([{ name: "left-pad", version: "1.3.0" }], lookup, policy);

    expect(report.results[0].status).toBe("unknown");
    expect(report.results[0].license).toBe("WTFPL");
  });

  test("marks a dependency with no discoverable license as unknown with a null license", async () => {
    const lookup = new InMemoryLicenseLookup({});
    const report = await checkCompliance([{ name: "mystery-pkg", version: "1.0.0" }], lookup, policy);

    expect(report.results[0]).toEqual({
      name: "mystery-pkg",
      version: "1.0.0",
      license: null,
      status: "unknown",
    });
  });

  test("aggregates a mixed set of dependencies into an accurate summary", async () => {
    const lookup = new InMemoryLicenseLookup({
      chalk: "MIT",
      "gpl-lib": "GPL-3.0",
      "left-pad": "WTFPL",
    });
    const report = await checkCompliance(
      [
        { name: "chalk", version: "4.1.0" },
        { name: "gpl-lib", version: "1.0.0" },
        { name: "left-pad", version: "1.3.0" },
      ],
      lookup,
      policy
    );

    expect(report.summary).toEqual({ total: 3, approved: 1, denied: 1, unknown: 1 });
  });
});
