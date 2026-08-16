import { describe, it, expect, beforeAll } from "bun:test";
import * as fs from "fs";
import * as path from "path";

// Test fixtures are loaded from disk
describe("Integration Tests - Matrix Generator with Fixtures", () => {
  let basicConfig: any;
  let complexConfig: any;
  let withOptions: any;
  let advancedOptions: any;

  beforeAll(() => {
    const fixtureDir = "./fixtures";
    basicConfig = JSON.parse(
      fs.readFileSync(path.join(fixtureDir, "basic-config.json"), "utf-8")
    );
    complexConfig = JSON.parse(
      fs.readFileSync(path.join(fixtureDir, "complex-config.json"), "utf-8")
    );
    withOptions = JSON.parse(
      fs.readFileSync(path.join(fixtureDir, "with-options.json"), "utf-8")
    );
    advancedOptions = JSON.parse(
      fs.readFileSync(path.join(fixtureDir, "advanced-options.json"), "utf-8")
    );
  });

  it("should load basic-config.json fixture", () => {
    expect(basicConfig.os).toBeDefined();
    expect(basicConfig.nodeVersion).toBeDefined();
    expect(basicConfig.os.length).toBe(2);
    expect(basicConfig.nodeVersion.length).toBe(2);
  });

  it("should load complex-config.json fixture", () => {
    expect(complexConfig.os.length).toBe(3);
    expect(complexConfig.nodeVersion.length).toBe(3);
    expect(complexConfig.pythonVersion.length).toBe(3);
  });

  it("should load with-options.json fixture", () => {
    expect(withOptions.exclude).toBeDefined();
    expect(withOptions.maxParallel).toBe(4);
    expect(withOptions.failFast).toBe(false);
  });

  it("should load advanced-options.json fixture", () => {
    expect(advancedOptions.include).toBeDefined();
    expect(advancedOptions.exclude).toBeDefined();
    expect(advancedOptions.maxParallel).toBe(5);
    expect(advancedOptions.failFast).toBe(true);
  });

  it("should have all required fixtures", () => {
    const fixtureDir = "./fixtures";
    const files = fs.readdirSync(fixtureDir);

    expect(files).toContain("basic-config.json");
    expect(files).toContain("complex-config.json");
    expect(files).toContain("with-options.json");
    expect(files).toContain("advanced-options.json");
  });

  it("fixture JSON is valid and parseable", () => {
    // If we got here without exceptions, JSON is valid
    expect(basicConfig).toBeDefined();
    expect(complexConfig).toBeDefined();
    expect(withOptions).toBeDefined();
    expect(advancedOptions).toBeDefined();
  });
});
