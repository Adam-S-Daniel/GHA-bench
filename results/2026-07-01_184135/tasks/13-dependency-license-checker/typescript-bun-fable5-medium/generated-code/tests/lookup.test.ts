// RED/GREEN cycle 4: production license lookup + config loading.
// In production the "license lookup" is a local JSON database file
// (name -> SPDX id). Loading it yields a LicenseLookup function with the
// same shape the tests mock elsewhere.
import { describe, expect, test } from "bun:test";
import { loadLicenseLookup } from "../src/lookup";
import { loadConfig } from "../src/config";

const fixture = (name: string): string =>
  new URL(`./fixtures/${name}`, import.meta.url).pathname;

describe("loadLicenseLookup", () => {
  test("resolves licenses from a JSON database file", async () => {
    const lookup = await loadLicenseLookup(fixture("sample-license-db.json"));
    expect(lookup({ name: "left-pad", version: "^1.3.0" })).toBe("MIT");
    expect(lookup({ name: "evil-lib", version: "2.0.0" })).toBe("GPL-3.0-only");
  });

  test("returns undefined for packages not in the database", async () => {
    const lookup = await loadLicenseLookup(fixture("sample-license-db.json"));
    expect(lookup({ name: "mystery-pkg", version: "0.1.0" })).toBeUndefined();
  });

  test("throws a meaningful error when the database file is missing", async () => {
    await expect(loadLicenseLookup("/no/such/db.json")).rejects.toThrow(
      /license database file not found/i,
    );
  });
});

describe("loadConfig", () => {
  test("loads allow/deny lists from a JSON config file", async () => {
    expect(await loadConfig(fixture("sample-config.json"))).toEqual({
      allow: ["MIT"],
      deny: ["GPL-3.0-only"],
    });
  });

  test("throws a meaningful error when the config file is missing", async () => {
    await expect(loadConfig("/no/such/config.json")).rejects.toThrow(
      /config file not found/i,
    );
  });

  test("throws a meaningful error when allow/deny lists are malformed", async () => {
    const bad = fixture("sample-license-db.json"); // valid JSON, wrong shape
    await expect(loadConfig(bad)).rejects.toThrow(
      /config must contain "allow" and "deny" arrays of strings/i,
    );
  });
});
