/**
 * Tests for the compliance checker (RED first: src/checker.ts does not exist).
 *
 * Approach: checkCompliance() takes dependencies, an allow/deny config, and a
 * LicenseLookup. The lookup is an interface, so these tests inject an
 * in-memory mock — no network, fully deterministic.
 */
import { describe, expect, test } from "bun:test";
import { checkCompliance } from "../src/checker";
import type { Dependency, LicenseConfig, LicenseLookup } from "../src/types";

/** In-memory mock of the license lookup used across the test suite. */
function mockLookup(db: Record<string, string>): LicenseLookup {
  return {
    getLicense: async (name: string): Promise<string | null> => db[name] ?? null,
  };
}

const config: LicenseConfig = {
  allow: ["MIT", "Apache-2.0"],
  deny: ["GPL-3.0"],
};

describe("checkCompliance", () => {
  test("classifies each dependency as approved, denied, or unknown", async () => {
    const deps: Dependency[] = [
      { name: "left-pad", version: "1.3.0" },
      { name: "mystery-lib", version: "0.0.1" },
      { name: "react", version: "18.2.0" },
      { name: "some-tool", version: "2.0.0" },
    ];
    const lookup = mockLookup({
      react: "MIT",
      "left-pad": "GPL-3.0",
      "some-tool": "BSD-3-Clause", // known license, but on neither list
    });

    const report = await checkCompliance(deps, config, lookup);

    expect(report.entries).toEqual([
      { name: "left-pad", version: "1.3.0", license: "GPL-3.0", status: "denied" },
      { name: "mystery-lib", version: "0.0.1", license: null, status: "unknown" },
      { name: "react", version: "18.2.0", license: "MIT", status: "approved" },
      { name: "some-tool", version: "2.0.0", license: "BSD-3-Clause", status: "unknown" },
    ]);
    expect(report.summary).toEqual({ approved: 1, denied: 1, unknown: 2 });
  });

  test("deny takes precedence when a license is on both lists", async () => {
    const bad: LicenseConfig = { allow: ["MIT"], deny: ["MIT"] };
    const report = await checkCompliance(
      [{ name: "react", version: "18.2.0" }],
      bad,
      mockLookup({ react: "MIT" }),
    );
    expect(report.entries[0].status).toBe("denied");
  });

  test("license matching is case-insensitive", async () => {
    const report = await checkCompliance(
      [{ name: "react", version: "18.2.0" }],
      { allow: ["mit"], deny: [] },
      mockLookup({ react: "MIT" }),
    );
    expect(report.entries[0].status).toBe("approved");
  });

  test("produces an empty report for zero dependencies", async () => {
    const report = await checkCompliance([], config, mockLookup({}));
    expect(report.entries).toEqual([]);
    expect(report.summary).toEqual({ approved: 0, denied: 0, unknown: 0 });
  });

  test("wraps lookup failures in a meaningful error", async () => {
    const failing: LicenseLookup = {
      getLicense: async () => {
        throw new Error("registry unreachable");
      },
    };
    await expect(
      checkCompliance([{ name: "react", version: "18.2.0" }], config, failing),
    ).rejects.toThrow(/license lookup failed for react@18.2.0.*registry unreachable/i);
  });
});
