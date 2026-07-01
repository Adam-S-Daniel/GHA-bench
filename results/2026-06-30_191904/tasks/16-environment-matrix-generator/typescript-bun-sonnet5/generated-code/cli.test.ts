// CLI-contract tests for `matrix-generator.ts`.
//
// These spawn the script as a real subprocess (the same way a human or a CI
// step would invoke it) to lock down its I/O contract: file/stdin reading,
// stdout shape, exit codes, and stderr error messages. This is separate from
// the mandatory act-driven pipeline tests in workflow.test.ts — those verify
// the *workflow* actually runs the script in CI; these verify the script's
// own command-line behavior in isolation, which is normal TDD for a CLI.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "matrix-generator.ts");

function run(args: string[], stdin?: string): { stdout: string; stderr: string; code: number } {
  const proc = Bun.spawnSync(["bun", "run", SCRIPT, ...args], {
    stdin: stdin === undefined ? undefined : Buffer.from(stdin),
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    stdout: new TextDecoder().decode(proc.stdout),
    stderr: new TextDecoder().decode(proc.stderr),
    code: proc.exitCode ?? -1,
  };
}

describe("CLI", () => {
  test("prints usage and exits 1 when no arguments are given", () => {
    const result = run([]);
    expect(result.code).toBe(1);
    expect(result.stderr).toContain("Usage");
  });

  test("reads a config file and prints the generated matrix JSON", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(
      configPath,
      JSON.stringify({ os: ["ubuntu-latest"], version: ["18", "20"] }),
    );
    const result = run([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(result.code).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.matrixSize).toBe(2);
    expect(parsed.matrix.include).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
    ]);
  });

  test("reads the config from stdin when given '-'", () => {
    const result = run(["-"], JSON.stringify({ os: ["ubuntu-latest"], version: ["18"] }));
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout).matrixSize).toBe(1);
  });

  test("exits 1 with a clear message when the file does not exist", () => {
    const result = run(["/nonexistent/config.json"]);
    expect(result.code).toBe(1);
    expect(result.stderr).toContain("/nonexistent/config.json");
  });

  test("exits 1 with a clear message on invalid JSON", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(configPath, "{ not valid json");
    const result = run([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(result.code).toBe(1);
    expect(result.stderr).toContain("Invalid JSON");
  });

  test("exits 1 with the size-exceeded message when maxMatrixSize is too small", () => {
    const dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
    const configPath = join(dir, "config.json");
    writeFileSync(
      configPath,
      JSON.stringify({ os: ["ubuntu-latest", "windows-latest"], version: ["18", "20"], maxMatrixSize: 1 }),
    );
    const result = run([configPath]);
    rmSync(dir, { recursive: true, force: true });

    expect(result.code).toBe(1);
    expect(result.stderr).toContain("4");
    expect(result.stderr).toContain("1");
  });
});
