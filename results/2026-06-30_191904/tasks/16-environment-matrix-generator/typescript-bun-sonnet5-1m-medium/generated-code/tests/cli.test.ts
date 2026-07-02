// Tests for the CLI entry point (src/cli.ts), which reads a JSON config from
// a file path argument (or stdin) and prints the generated matrix JSON.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI_PATH = join(import.meta.dir, "..", "src", "cli.ts");

function runCli(args: string[]): { stdout: string; stderr: string; exitCode: number } {
  const proc = Bun.spawnSync(["bun", "run", CLI_PATH, ...args]);
  return {
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
    exitCode: proc.exitCode ?? -1,
  };
}

describe("CLI", () => {
  test("reads a config file path and prints the matrix JSON to stdout", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(
      configPath,
      JSON.stringify({
        dimensions: { os: ["ubuntu-latest"], node: ["18", "20"] },
      }),
    );

    const { stdout, exitCode } = runCli([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.matrix.include).toHaveLength(2);
    expect(parsed.matrix["fail-fast"]).toBe(true);
  });

  test("exits non-zero with a clear error message for a missing config file", () => {
    const { stderr, exitCode } = runCli(["/nonexistent/path/config.json"]);

    expect(exitCode).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("config");
  });

  test("exits non-zero with a clear error message for invalid JSON", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(configPath, "{ this is not valid json");

    const { stderr, exitCode } = runCli([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(exitCode).not.toBe(0);
    expect(stderr.length).toBeGreaterThan(0);
  });

  test("exits non-zero with a clear error message when the matrix exceeds maxMatrixSize", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(
      configPath,
      JSON.stringify({
        dimensions: { os: ["a", "b", "c"], node: ["1", "2", "3"] },
        maxMatrixSize: 2,
      }),
    );

    const { stderr, exitCode } = runCli([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(exitCode).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("exceeds maximum matrix size");
  });

  test("--compact prints only the matrix object as a single line of JSON", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(
      configPath,
      JSON.stringify({ dimensions: { os: ["ubuntu-latest"] } }),
    );

    const { stdout, exitCode } = runCli([configPath, "--compact"]);
    rmSync(dir, { recursive: true, force: true });

    expect(exitCode).toBe(0);
    expect(stdout.trim().split("\n")).toHaveLength(1);
    const parsed = JSON.parse(stdout);
    expect(parsed).toEqual({
      include: [{ os: "ubuntu-latest" }],
      "fail-fast": true,
    });
  });
});
