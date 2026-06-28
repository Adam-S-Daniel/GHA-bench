/**
 * Tests for the license lookup seam.
 *
 * In production a lookup might hit npm's registry or a SPDX scanner. For
 * deterministic tests and offline CI we drive it from a static database:
 * createDatabaseLookup(db) returns a LicenseLookup that resolves a dependency's
 * license, preferring an exact name@version match, then a bare-name match, and
 * returning null (unknown) when neither is present.
 */
import { describe, expect, it } from "bun:test";
import { createDatabaseLookup } from "../src/lookup.ts";
import type { Dependency, LicenseDatabase } from "../src/lookup.ts";

const db: LicenseDatabase = {
  "left-pad@1.3.0": "MIT",
  lodash: "MIT",
  "evil-pkg@2.0.0": "GPL-3.0",
};

describe("createDatabaseLookup", () => {
  const lookup = createDatabaseLookup(db);

  it("resolves an exact name@version match", () => {
    const dep: Dependency = { name: "left-pad", version: "1.3.0" };
    expect(lookup(dep)).toBe("MIT");
  });

  it("falls back to a bare-name match when the version is not pinned", () => {
    const dep: Dependency = { name: "lodash", version: "4.17.21" };
    expect(lookup(dep)).toBe("MIT");
  });

  it("prefers the exact version match over the bare-name match", () => {
    const mixed: LicenseDatabase = { "pkg@1.0.0": "MIT", pkg: "GPL-3.0" };
    const l = createDatabaseLookup(mixed);
    expect(l({ name: "pkg", version: "1.0.0" })).toBe("MIT");
  });

  it("returns null for an unknown dependency", () => {
    expect(lookup({ name: "mystery", version: "0.0.1" })).toBeNull();
  });
});
