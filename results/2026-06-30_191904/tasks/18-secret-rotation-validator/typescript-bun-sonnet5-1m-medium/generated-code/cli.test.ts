import { describe, expect, test } from "bun:test";
import { loadConfig, parseArgs, runValidator } from "./cli.ts";

const REFERENCE_DATE = new Date("2026-07-01T00:00:00.000Z");

describe("parseArgs", () => {
  test("parses config path, format, and warning-days overrides", () => {
    const options = parseArgs([
      "fixtures/mixed.json",
      "--format",
      "json",
      "--warning-days",
      "30",
    ]);

    expect(options.configPath).toBe("fixtures/mixed.json");
    expect(options.format).toBe("json");
    expect(options.warningDaysOverride).toBe(30);
  });

  test("defaults to markdown format when --format is omitted", () => {
    const options = parseArgs(["fixtures/mixed.json"]);

    expect(options.format).toBe("markdown");
    expect(options.warningDaysOverride).toBeUndefined();
  });

  test("throws a clear error when no config path is given", () => {
    expect(() => parseArgs([])).toThrow(/config path/);
  });

  test("parses a --now override for deterministic reference dates", () => {
    const options = parseArgs(["fixtures/mixed.json", "--now", "2026-07-01T00:00:00.000Z"]);

    expect(options.now).toEqual(REFERENCE_DATE);
  });

  test("throws a clear error for an unparseable --now value", () => {
    expect(() => parseArgs(["fixtures/mixed.json", "--now", "not-a-date"])).toThrow(/Invalid --now/);
  });
});

describe("loadConfig", () => {
  test("reads and parses a JSON config file", async () => {
    const config = await loadConfig("fixtures/mixed.json");

    expect(config.warningWindowDays).toBe(14);
    expect(config.secrets).toHaveLength(3);
  });

  test("throws a clear error for a missing config file", async () => {
    await expect(loadConfig("fixtures/does-not-exist.json")).rejects.toThrow(/not found/);
  });
});

describe("runValidator", () => {
  test("exits 1 and reports expired secrets when any secret is expired", async () => {
    const result = await runValidator(
      { configPath: "fixtures/mixed.json", format: "json" },
      REFERENCE_DATE,
    );

    expect(result.exitCode).toBe(1);
    expect(result.report.expired.map((s) => s.name)).toEqual(["db-password"]);
  });

  test("exits 0 when no secret is expired", async () => {
    const result = await runValidator(
      { configPath: "fixtures/all-ok.json", format: "json" },
      REFERENCE_DATE,
    );

    expect(result.exitCode).toBe(0);
    expect(result.report.expired).toHaveLength(0);
  });

  test("applies a warning-days override from CLI options", async () => {
    const result = await runValidator(
      { configPath: "fixtures/mixed.json", format: "json", warningDaysOverride: 85 },
      REFERENCE_DATE,
    );

    // With an 85-day window, tls-cert (80 days left) now falls into warning too.
    expect(result.report.warning.map((s) => s.name).sort()).toEqual(["api-key", "tls-cert"]);
  });

  test("produces markdown output when format is markdown", async () => {
    const result = await runValidator(
      { configPath: "fixtures/mixed.json", format: "markdown" },
      REFERENCE_DATE,
    );

    expect(result.output).toContain("# Secret Rotation Report");
  });
});
