/**
 * TDD cycle 5 (RED): directory collection + CLI end-to-end.
 *
 * `collectResults(dir)` reads every *.xml (JUnit) and *.json (JSON results)
 * file in a directory, sorted by name for determinism.
 *
 * The CLI (`bun run src/cli.ts --dir <dir> --out <file>`) prints the markdown
 * summary plus one machine-readable "RESULT ..." line, writes the summary
 * file, and exits non-zero with a clear message on bad input.
 *
 * Expected exact values for fixtures/matrix (3 files, 12 cases):
 *   passed=7 failed=3 skipped=2 duration=6.60s flaky=1 (net :: retry, 2p/1f)
 */
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { collectResults } from "../src/cli";

const ROOT = join(import.meta.dir, "..");
const MATRIX_DIR = join(ROOT, "fixtures", "matrix");

/** Run the CLI as a subprocess, the same way the workflow invokes it. */
async function runCli(
  args: string[],
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn(["bun", "run", join(ROOT, "src", "cli.ts"), ...args], {
    cwd: ROOT,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, GITHUB_STEP_SUMMARY: "" },
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, stdout, stderr };
}

describe("collectResults", () => {
  test("parses every xml/json file in the matrix fixture dir", () => {
    const files = collectResults(MATRIX_DIR);
    expect(files.map((f) => f.source)).toEqual([
      "junit-macos.xml",
      "junit-ubuntu.xml",
      "results-windows.json",
    ]);
    expect(files.reduce((n, f) => n + f.cases.length, 0)).toBe(12);
  });

  test("ignores non-result files but fails on a corrupt result file", () => {
    const dir = mkdtempSync(join(tmpdir(), "agg-"));
    try {
      writeFileSync(join(dir, "README.md"), "not a result");
      writeFileSync(join(dir, "broken.json"), "{nope");
      expect(() => collectResults(dir)).toThrow(/broken\.json/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("throws a clear error for a missing directory", () => {
    expect(() => collectResults(join(ROOT, "no-such-dir"))).toThrow(
      /no-such-dir.*not a readable directory/i,
    );
  });
});

describe("cli end-to-end", () => {
  test("aggregates the matrix fixtures with exact totals", async () => {
    const dir = mkdtempSync(join(tmpdir(), "agg-out-"));
    try {
      const out = join(dir, "summary.md");
      const { exitCode, stdout } = await runCli([
        "--dir",
        MATRIX_DIR,
        "--out",
        out,
      ]);
      expect(exitCode).toBe(0);
      // machine-readable line asserted on by the act harness
      expect(stdout).toContain(
        "RESULT total=12 passed=7 failed=3 skipped=2 duration=6.60 flaky=1",
      );
      const md = readFileSync(out, "utf8");
      expect(md).toContain("| Total tests | 12 |");
      expect(md).toContain("| `net :: retry` | 2 | 1 |");
      expect(stdout).toContain(md.trim());
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("exits 1 with a helpful message when the directory is missing", async () => {
    const { exitCode, stderr } = await runCli(["--dir", "does-not-exist"]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain("does-not-exist");
  });

  test("exits 1 when --dir is not provided", async () => {
    const { exitCode, stderr } = await runCli([]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain("Usage:");
  });
});
