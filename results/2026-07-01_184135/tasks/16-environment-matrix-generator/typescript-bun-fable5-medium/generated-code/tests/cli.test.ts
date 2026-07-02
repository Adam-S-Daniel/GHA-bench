/**
 * CLI tests (TDD cycle 6): written before src/cli.ts existed.
 *
 * The CLI is exercised as a real subprocess (`bun run src/cli.ts <file>`)
 * because that is exactly how the GitHub Actions workflow invokes it —
 * the temp-dir fixtures below stand in for the config file in the repo.
 */
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = join(import.meta.dir, "..", "src", "cli.ts");
const tempDir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
afterAll(() => rmSync(tempDir, { recursive: true, force: true }));

/** Write a fixture config file and return its path. */
function fixture(name: string, contents: string): string {
  const path = join(tempDir, name);
  writeFileSync(path, contents);
  return path;
}

function runCli(...args: string[]) {
  const proc = Bun.spawnSync(["bun", "run", CLI, ...args]);
  return {
    code: proc.exitCode,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

describe("cli", () => {
  test("prints the complete matrix JSON for a valid config", () => {
    const path = fixture(
      "valid.json",
      JSON.stringify({
        os: ["ubuntu-latest"],
        versions: ["20"],
        features: ["stable"],
        "fail-fast": false,
        "max-parallel": 3,
      }),
    );
    const { code, stdout } = runCli(path);
    expect(code).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed).toEqual({
      strategy: {
        "fail-fast": false,
        "max-parallel": 3,
        matrix: { os: ["ubuntu-latest"], version: ["20"], feature: ["stable"] },
      },
      combinations: [{ os: "ubuntu-latest", version: "20", feature: "stable" }],
      count: 1,
    });
  });

  test("fails with a clear message when the config file is missing", () => {
    const { code, stderr } = runCli(join(tempDir, "nope.json"));
    expect(code).toBe(1);
    expect(stderr).toContain("Cannot read config file");
  });

  test("fails with a clear message on invalid JSON", () => {
    const path = fixture("bad.json", "{ not json !");
    const { code, stderr } = runCli(path);
    expect(code).toBe(1);
    expect(stderr).toContain("is not valid JSON");
  });

  test("fails with the MatrixError message on an oversized matrix", () => {
    const path = fixture(
      "oversized.json",
      JSON.stringify({
        os: ["a", "b", "c"],
        versions: ["1", "2", "3", "4"],
        features: ["x", "y", "z"],
        "max-size": 10,
      }),
    );
    const { code, stderr } = runCli(path);
    expect(code).toBe(1);
    expect(stderr).toContain("Matrix size 36 exceeds maximum allowed size 10");
  });

  test("fails with usage when no argument is given", () => {
    const { code, stderr } = runCli();
    expect(code).toBe(1);
    expect(stderr).toContain("Usage:");
  });
});
