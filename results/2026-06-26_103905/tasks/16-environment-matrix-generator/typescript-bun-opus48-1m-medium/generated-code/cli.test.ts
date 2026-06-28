// TDD tests for the command-line interface of the matrix generator.
//
// The CLI reads a JSON config file path (or stdin) and prints the generated
// matrix JSON to stdout. Errors go to stderr with a non-zero exit code.
import { describe, expect, test, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = join(import.meta.dir, "matrix-generator.ts");
let dir: string;

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "matrix-cli-"));
});
afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

/** Run the CLI with the given args and return its result. */
async function runCli(args: string[], input?: string) {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], {
    stdin: input ? new TextEncoder().encode(input) : undefined,
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;
  return { stdout, stderr, exitCode };
}

describe("CLI", () => {
  // RED #5: reading a config file and printing matrix JSON.
  test("reads a config file and prints the generated matrix JSON", async () => {
    const cfg = join(dir, "ok.json");
    writeFileSync(
      cfg,
      JSON.stringify({
        matrix: { os: ["linux", "windows"], node: ["18", "20"] },
        failFast: false,
        maxParallel: 3,
      }),
    );
    const { stdout, exitCode } = await runCli([cfg]);
    expect(exitCode).toBe(0);
    const parsed = JSON.parse(stdout);
    expect(parsed.size).toBe(4);
    expect(parsed.failFast).toBe(false);
    expect(parsed.maxParallel).toBe(3);
    expect(parsed.include).toHaveLength(4);
  });

  test("reads the config from stdin when given '-'", async () => {
    const input = JSON.stringify({ matrix: { os: ["linux"] } });
    const { stdout, exitCode } = await runCli(["-"], input);
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).size).toBe(1);
  });

  test("exits non-zero with a message when the file is missing", async () => {
    const { stderr, exitCode } = await runCli([join(dir, "nope.json")]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/Failed to read config|no such file|ENOENT/i);
  });

  test("exits non-zero with a message on invalid JSON", async () => {
    const cfg = join(dir, "bad.json");
    writeFileSync(cfg, "{not valid json");
    const { stderr, exitCode } = await runCli([cfg]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/JSON/i);
  });

  test("exits non-zero with the size error when maxSize is exceeded", async () => {
    const cfg = join(dir, "toobig.json");
    writeFileSync(
      cfg,
      JSON.stringify({ matrix: { os: ["a", "b", "c"] }, maxSize: 2 }),
    );
    const { stderr, exitCode } = await runCli([cfg]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/exceeds the maximum/i);
  });

  test("prints usage when no arguments are given", async () => {
    const { stderr, exitCode } = await runCli([]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/usage/i);
  });
});
