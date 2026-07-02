/**
 * CLI tests (TDD cycle 6): run the real CLI with `bun run src/cli.ts` and
 * assert on stdout / stderr / exit codes. Fixture configs live in fixtures/
 * and are the same ones exercised end-to-end through the GitHub Actions
 * workflow (via act).
 */
import { describe, expect, test } from "bun:test";
import { spawnSync } from "bun";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");

/** Run the CLI with the given args, returning exit code and output. */
function runCli(args: string[]): { code: number; stdout: string; stderr: string } {
  const proc = spawnSync(["bun", "run", join(ROOT, "src/cli.ts"), ...args], {
    cwd: ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: proc.exitCode ?? -1,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

describe("cli", () => {
  test("basic fixture prints the complete strategy JSON on one line", () => {
    const { code, stdout } = runCli(["fixtures/basic.json"]);
    expect(code).toBe(0);

    const parsed = JSON.parse(stdout);
    expect(parsed.jobCount).toBe(4);
    expect(parsed.strategy["fail-fast"]).toBe(false);
    expect(parsed.strategy["max-parallel"]).toBe(2);
    expect(parsed.strategy.matrix.include).toHaveLength(4);
    expect(parsed.strategy.matrix.include[0]).toEqual({
      os: "ubuntu-latest",
      "language-version": "18",
      feature: "telemetry",
    });
    // Output must be a single line of compact JSON (easy to grep in CI logs).
    expect(stdout.trim().split("\n")).toHaveLength(1);
  });

  test("include/exclude fixture produces the exact expected combinations", () => {
    const { code, stdout } = runCli(["fixtures/include-exclude.json"]);
    expect(code).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.strategy.matrix.include).toEqual([
      { os: "ubuntu-latest", "language-version": "18", experimental: "true" },
      { os: "ubuntu-latest", "language-version": "20", experimental: "true" },
      { os: "macos-latest", "language-version": "20" },
    ]);
    expect(parsed.jobCount).toBe(3);
  });

  test("oversized fixture fails with a size error on stderr and exit code 1", () => {
    const { code, stdout, stderr } = runCli(["fixtures/oversized.json"]);
    expect(code).toBe(1);
    expect(stdout).toBe("");
    expect(stderr).toContain("Matrix size 12 exceeds the maximum allowed size 10");
  });

  test("missing config file yields a meaningful error", () => {
    const { code, stderr } = runCli(["fixtures/does-not-exist.json"]);
    expect(code).toBe(1);
    expect(stderr).toContain("Cannot read config file");
  });

  test("invalid JSON yields a meaningful error", async () => {
    const badPath = join(ROOT, "fixtures", ".invalid.tmp.json");
    await Bun.write(badPath, "{ not json !");
    try {
      const { code, stderr } = runCli([badPath]);
      expect(code).toBe(1);
      expect(stderr).toContain("not valid JSON");
    } finally {
      await Bun.file(badPath).delete();
    }
  });

  test("no argument yields usage guidance", () => {
    const { code, stderr } = runCli([]);
    expect(code).toBe(1);
    expect(stderr).toContain("Usage:");
  });

  test("--matrix-only prints just the matrix object for fromJSON()", () => {
    const { code, stdout } = runCli(["fixtures/include-exclude.json", "--matrix-only"]);
    expect(code).toBe(0);
    const parsed = JSON.parse(stdout);
    // Exactly the shape strategy.matrix expects: { include: [...] }.
    expect(Object.keys(parsed)).toEqual(["include"]);
    expect(parsed.include).toHaveLength(3);
  });

  test("--pretty prints indented JSON", () => {
    const { code, stdout } = runCli(["fixtures/basic.json", "--pretty"]);
    expect(code).toBe(0);
    expect(stdout).toContain('\n  "strategy"');
  });
});
