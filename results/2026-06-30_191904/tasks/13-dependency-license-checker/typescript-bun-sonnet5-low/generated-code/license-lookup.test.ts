import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createNodeModulesLicenseLookup } from "./license-lookup";

const FIXTURE_ROOT = join(import.meta.dir, "fixtures", "node_modules_lookup");

describe("createNodeModulesLicenseLookup", () => {
  beforeAll(() => {
    mkdirSync(join(FIXTURE_ROOT, "node_modules", "has-license"), { recursive: true });
    writeFileSync(
      join(FIXTURE_ROOT, "node_modules", "has-license", "package.json"),
      JSON.stringify({ name: "has-license", version: "1.0.0", license: "MIT" })
    );

    mkdirSync(join(FIXTURE_ROOT, "node_modules", "object-license"), { recursive: true });
    writeFileSync(
      join(FIXTURE_ROOT, "node_modules", "object-license", "package.json"),
      JSON.stringify({ name: "object-license", version: "1.0.0", license: { type: "Apache-2.0" } })
    );
  });

  afterAll(() => {
    rmSync(FIXTURE_ROOT, { recursive: true, force: true });
  });

  test("reads a string license field from an installed package's package.json", async () => {
    const lookup = createNodeModulesLicenseLookup(FIXTURE_ROOT);
    const license = await lookup({ name: "has-license", version: "1.0.0" });
    expect(license).toBe("MIT");
  });

  test("reads a legacy object-form license field", async () => {
    const lookup = createNodeModulesLicenseLookup(FIXTURE_ROOT);
    const license = await lookup({ name: "object-license", version: "1.0.0" });
    expect(license).toBe("Apache-2.0");
  });

  test("returns null when the package is not installed locally", async () => {
    const lookup = createNodeModulesLicenseLookup(FIXTURE_ROOT);
    const license = await lookup({ name: "not-installed", version: "1.0.0" });
    expect(license).toBeNull();
  });
});
