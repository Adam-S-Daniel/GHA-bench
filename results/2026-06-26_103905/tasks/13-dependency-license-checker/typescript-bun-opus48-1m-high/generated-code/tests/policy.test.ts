/**
 * Tests for the license policy classifier.
 *
 * Given a resolved license string (or null) and a policy, classify() must
 * decide approved / denied / unknown. Deny-list takes precedence over the
 * allow-list so that an explicitly forbidden license is never approved even if
 * it somehow also appears on the allow-list. Comparison is case-insensitive.
 */
import { describe, expect, it } from "bun:test";
import { classify, loadPolicy } from "../src/policy.ts";
import type { LicensePolicy } from "../src/types.ts";

const policy: LicensePolicy = {
  allow: ["MIT", "Apache-2.0", "BSD-3-Clause"],
  deny: ["GPL-3.0", "AGPL-3.0"],
};

describe("classify", () => {
  it("returns 'approved' for a license on the allow-list", () => {
    expect(classify("MIT", policy)).toBe("approved");
  });

  it("is case-insensitive", () => {
    expect(classify("mit", policy)).toBe("approved");
    expect(classify("gpl-3.0", policy)).toBe("denied");
  });

  it("returns 'denied' for a license on the deny-list", () => {
    expect(classify("GPL-3.0", policy)).toBe("denied");
  });

  it("lets the deny-list win over the allow-list", () => {
    const conflicted: LicensePolicy = { allow: ["MIT"], deny: ["MIT"] };
    expect(classify("MIT", conflicted)).toBe("denied");
  });

  it("returns 'unknown' for a null license", () => {
    expect(classify(null, policy)).toBe("unknown");
  });

  it("returns 'unknown' for a license on neither list", () => {
    expect(classify("WTFPL", policy)).toBe("unknown");
  });
});

describe("loadPolicy", () => {
  it("parses a valid policy JSON string and defaults failOnUnknown to false", () => {
    const json = JSON.stringify({ allow: ["MIT"], deny: ["GPL-3.0"] });
    const loaded = loadPolicy(json);
    expect(loaded.allow).toEqual(["MIT"]);
    expect(loaded.deny).toEqual(["GPL-3.0"]);
    expect(loaded.failOnUnknown).toBe(false);
  });

  it("preserves an explicit failOnUnknown flag", () => {
    const json = JSON.stringify({ allow: [], deny: [], failOnUnknown: true });
    expect(loadPolicy(json).failOnUnknown).toBe(true);
  });

  it("throws a meaningful error when allow/deny are missing", () => {
    expect(() => loadPolicy(JSON.stringify({ allow: ["MIT"] }))).toThrow(
      /policy.*"deny"/i,
    );
  });

  it("throws a meaningful error on invalid JSON", () => {
    expect(() => loadPolicy("{ nope")).toThrow(/Failed to parse policy/);
  });
});
