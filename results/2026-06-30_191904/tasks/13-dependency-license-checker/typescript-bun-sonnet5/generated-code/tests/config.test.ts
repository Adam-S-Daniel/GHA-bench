import { describe, expect, test } from "bun:test";
import { loadLicenseConfig } from "../src/config";

// RED: fails until src/config.ts exports loadLicenseConfig.
describe("loadLicenseConfig", () => {
  test("reads allowlist and denylist arrays from a JSON policy file", () => {
    const config = loadLicenseConfig("tests/fixtures/license-policy.sample.json");

    expect(config).toEqual({
      allowlist: ["MIT", "Apache-2.0"],
      denylist: ["GPL-3.0"],
    });
  });

  test("throws a clear error for a missing file", () => {
    expect(() => loadLicenseConfig("tests/fixtures/no-such-policy.json")).toThrow(
      /not found/i,
    );
  });

  test("throws a clear error when allowlist or denylist is missing", () => {
    expect(() => loadLicenseConfig("tests/fixtures/license-policy.invalid.json")).toThrow(
      /must have "allowlist" and "denylist"/i,
    );
  });
});
