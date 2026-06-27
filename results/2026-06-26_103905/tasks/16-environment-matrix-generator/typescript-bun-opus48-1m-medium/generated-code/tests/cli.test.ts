import { describe, expect, test } from "bun:test";
import { join } from "node:path";

const CLI = join(import.meta.dir, "..", "src", "cli.ts");
const FIXTURES = join(import.meta.dir, "..", "fixtures");

/** Run the CLI with the given args; capture stdout, stderr and exit code. */
async function runCli(args: string[]): Promise<{
  stdout: string;
  stderr: string;
  code: number;
}> {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;
  return { stdout, stderr, code };
}

describe("cli", () => {
  test("prints valid strategy JSON for a config file", async () => {
    const { stdout, code } = await runCli([join(FIXTURES, "basic.json")]);
    expect(code).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "20" },
      { os: "ubuntu-latest", language: "22" },
    ]);
    expect(parsed["fail-fast"]).toBe(false);
    expect(parsed["max-parallel"]).toBe(2);
  });

  test("exits non-zero with a message when the matrix is too large", async () => {
    const { stderr, code } = await runCli([join(FIXTURES, "too-large.json")]);
    expect(code).not.toBe(0);
    expect(stderr).toContain("exceeds");
  });

  test("exits non-zero with a message when the file is missing", async () => {
    const { stderr, code } = await runCli(["does-not-exist.json"]);
    expect(code).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("error");
  });

  test("exits non-zero when no config path is given", async () => {
    const { stderr, code } = await runCli([]);
    expect(code).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("usage");
  });
});
