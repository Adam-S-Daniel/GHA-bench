/**
 * TDD Cycle 4 (RED): the CLI entry point.
 *
 * `bun run src/cli.ts --files <files.json> --rules <rules.json>` prints:
 *   LABELS: a,b,c        (or `LABELS: <none>` when empty)
 *   LABEL_COUNT: N
 *   JSON: ["a","b","c"]
 * and exits 0. Invalid input exits 1 with an `error: ...` message on stderr.
 */
import { describe, expect, test } from "bun:test";

const CLI = new URL("../src/cli.ts", import.meta.url).pathname;
const fixture = (rel: string): string =>
  new URL(`../fixtures/${rel}`, import.meta.url).pathname;

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Run the CLI in a subprocess and capture its output. */
async function runCli(args: string[]): Promise<CliResult> {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { exitCode, stdout, stderr };
}

describe("cli", () => {
  test("case1: basic mapping produces the exact expected label set", async () => {
    const { exitCode, stdout } = await runCli([
      "--files", fixture("case1/changed-files.json"),
      "--rules", fixture("case1/rules.json"),
    ]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("LABELS: api,backend,documentation,tests");
    expect(stdout).toContain("LABEL_COUNT: 4");
    expect(stdout).toContain('JSON: ["api","backend","documentation","tests"]');
  });

  test("case2: priority conflict resolved in favor of higher priority", async () => {
    const { exitCode, stdout } = await runCli([
      "--files", fixture("case2/changed-files.json"),
      "--rules", fixture("case2/rules.json"),
    ]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("LABELS: generated,source");
    expect(stdout).toContain("LABEL_COUNT: 2");
  });

  test("case3: no matching rules yields an explicit empty set", async () => {
    const { exitCode, stdout } = await runCli([
      "--files", fixture("case3/changed-files.json"),
      "--rules", fixture("case3/rules.json"),
    ]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("LABELS: <none>");
    expect(stdout).toContain("LABEL_COUNT: 0");
    expect(stdout).toContain("JSON: []");
  });

  test("missing arguments exit 1 with a usage error", async () => {
    const { exitCode, stderr } = await runCli([]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/error: .*--files/i);
  });

  test("nonexistent input file exits 1 with a readable message", async () => {
    const { exitCode, stderr } = await runCli([
      "--files", "does-not-exist.json",
      "--rules", fixture("case1/rules.json"),
    ]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/error: cannot read .*does-not-exist\.json/i);
  });

  test("malformed JSON exits 1 with a parse error naming the file", async () => {
    const bad = `${import.meta.dir}/tmp-bad.json`;
    await Bun.write(bad, "{ not json");
    const { exitCode, stderr } = await runCli([
      "--files", bad,
      "--rules", fixture("case1/rules.json"),
    ]);
    expect(exitCode).toBe(1);
    expect(stderr).toMatch(/error: invalid JSON in .*tmp-bad\.json/i);
  });
});
