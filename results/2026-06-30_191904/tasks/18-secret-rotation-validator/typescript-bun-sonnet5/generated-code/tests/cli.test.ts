// Red/green TDD step 6: CLI argument parsing and the pure `run()` pipeline
// (load config -> generate report -> format output). `main()` itself is a
// thin process-exit wrapper around `run()` and is exercised end-to-end via
// the GitHub Actions workflow under `act` (see tests/workflow-act.test.ts),
// per the task's "test through the pipeline" requirement.
import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CliUsageError, parseArgs, run } from "../app.ts";

async function withFixture(contents: unknown, fn: (path: string) => Promise<void>): Promise<void> {
  const dir = await mkdtemp(join(tmpdir(), "secret-rotation-cli-"));
  try {
    const path = join(dir, "config.json");
    await writeFile(path, JSON.stringify(contents));
    await fn(path);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

describe("parseArgs", () => {
  test("parses --config, --format, --warning-window, --now", () => {
    const options = parseArgs([
      "--config",
      "fixtures/secrets-mixed.json",
      "--format",
      "json",
      "--warning-window",
      "7",
      "--now",
      "2026-07-01",
    ]);
    expect(options.configPath).toBe("fixtures/secrets-mixed.json");
    expect(options.format).toBe("json");
    expect(options.warningWindowDays).toBe(7);
    expect(options.now.toISOString()).toBe("2026-07-01T00:00:00.000Z");
  });

  test("defaults format to markdown and warningWindowDays to undefined (config decides)", () => {
    const options = parseArgs(["--config", "fixtures/secrets-mixed.json"]);
    expect(options.format).toBe("markdown");
    expect(options.warningWindowDays).toBeUndefined();
  });

  test("throws a usage error when --config is missing", () => {
    expect(() => parseArgs([])).toThrow(CliUsageError);
    expect(() => parseArgs([])).toThrow(/--config/);
  });

  test("throws a usage error for an unrecognized --format value", () => {
    expect(() => parseArgs(["--config", "x.json", "--format", "xml"])).toThrow(
      /format must be "markdown" or "json"/i,
    );
  });
});

describe("run", () => {
  test("returns exit code 0 and markdown output for a valid config", async () => {
    await withFixture(
      {
        warningWindowDays: 14,
        secrets: [
          { name: "tls-cert", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["web"] },
        ],
      },
      async (configPath) => {
        const result = await run({
          configPath,
          format: "markdown",
          now: new Date("2026-07-01T00:00:00.000Z"),
        });
        expect(result.exitCode).toBe(0);
        expect(result.output).toContain("# Secret Rotation Report");
        expect(result.output).toContain("tls-cert");
      },
    );
  });

  test("returns exit code 0 and JSON output when format is json", async () => {
    await withFixture(
      { secrets: [{ name: "s", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: [] }] },
      async (configPath) => {
        const result = await run({
          configPath,
          format: "json",
          now: new Date("2026-07-01T00:00:00.000Z"),
        });
        expect(result.exitCode).toBe(0);
        expect(() => JSON.parse(result.output)).not.toThrow();
      },
    );
  });

  test("applies a CLI warning-window override over the config value", async () => {
    await withFixture(
      {
        warningWindowDays: 14,
        secrets: [
          { name: "api-key", lastRotated: "2026-04-12", rotationPolicyDays: 90, requiredBy: [] },
        ],
      },
      async (configPath) => {
        const result = await run({
          configPath,
          format: "json",
          warningWindowDays: 5,
          now: new Date("2026-07-01T00:00:00.000Z"),
        });
        const parsed = JSON.parse(result.output);
        expect(parsed.warningWindowDays).toBe(5);
        expect(parsed.ok.map((s: { name: string }) => s.name)).toEqual(["api-key"]);
      },
    );
  });

  test("returns exit code 1 and a meaningful message when the config file is missing", async () => {
    const result = await run({
      configPath: "/nonexistent/config.json",
      format: "markdown",
      now: new Date("2026-07-01T00:00:00.000Z"),
    });
    expect(result.exitCode).toBe(1);
    expect(result.output).toMatch(/could not read config file/i);
  });

  test("returns exit code 1 and a meaningful message for an invalid config", async () => {
    await withFixture(
      { secrets: [{ name: "bad", lastRotated: "2026-06-01", rotationPolicyDays: -1, requiredBy: [] }] },
      async (configPath) => {
        const result = await run({
          configPath,
          format: "markdown",
          now: new Date("2026-07-01T00:00:00.000Z"),
        });
        expect(result.exitCode).toBe(1);
        expect(result.output).toMatch(/rotationPolicyDays/);
      },
    );
  });
});
