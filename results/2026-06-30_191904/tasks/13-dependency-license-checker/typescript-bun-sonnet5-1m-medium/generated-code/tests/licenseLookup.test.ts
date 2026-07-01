// TDD step 2: license lookup abstraction. The real implementation is backed
// by a JSON fixture file (offline, deterministic) so CI never needs network
// access; tests use an in-memory mock of the same interface.
import { describe, expect, test } from "bun:test";
import { InMemoryLicenseLookup, FixtureLicenseLookup } from "../src/licenseLookup";

describe("InMemoryLicenseLookup", () => {
  test("returns the license for a known name@version pair", async () => {
    const lookup = new InMemoryLicenseLookup({ "lodash@4.17.21": "MIT" });
    const license = await lookup.lookup({ name: "lodash", version: "4.17.21" });
    expect(license).toBe("MIT");
  });

  test("falls back to a name-only entry when no exact version match exists", async () => {
    const lookup = new InMemoryLicenseLookup({ lodash: "MIT" });
    const license = await lookup.lookup({ name: "lodash", version: "9.9.9" });
    expect(license).toBe("MIT");
  });

  test("returns null for an unknown dependency", async () => {
    const lookup = new InMemoryLicenseLookup({});
    const license = await lookup.lookup({ name: "mystery-pkg", version: "1.0.0" });
    expect(license).toBeNull();
  });
});

describe("FixtureLicenseLookup", () => {
  test("loads a license map from a JSON fixture file", async () => {
    const lookup = await FixtureLicenseLookup.fromFile("fixtures/license-db.json");
    const license = await lookup.lookup({ name: "express", version: "4.18.2" });
    expect(license).toBe("MIT");
  });

  test("throws a meaningful error when the fixture file is missing", async () => {
    await expect(FixtureLicenseLookup.fromFile("fixtures/does-not-exist.json")).rejects.toThrow(
      /license fixture/i
    );
  });
});
