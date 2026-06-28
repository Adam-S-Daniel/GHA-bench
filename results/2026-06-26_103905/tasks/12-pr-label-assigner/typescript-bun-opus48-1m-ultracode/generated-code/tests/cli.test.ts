// Tests for the CLI entrypoint (`cli.ts`).
//
// The CLI is the surface the GitHub Actions workflow drives, so these tests
// lock its output *contract*: the machine-readable `RESULT_LABELS=` and
// `RESULT_COUNT=` marker lines that the `act` harness parses. They run the CLI
// as a real subprocess (fast — no `act`, no Docker) so the contract is verified
// independently of the pipeline.

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = join(import.meta.dir, "..", "cli.ts");

const dir = mkdtempSync(join(tmpdir(), "labeler-cli-"));
const configPath = join(dir, "labeler.config.json");
const filesPath = join(dir, "changed-files.txt");

beforeAll(() => {
  writeFileSync(
    configPath,
    JSON.stringify({
      rules: [
        { label: "documentation", patterns: ["docs/**", "*.md"] },
        { label: "api", patterns: ["src/api/**"], priority: 10 },
        { label: "tests", patterns: ["*.test.*"] },
      ],
    }),
  );
});

afterAll(() => rmSync(dir, { recursive: true, force: true }));

/** Run the CLI as a subprocess, returning its exit code and captured output. */
function runCli(args: string[]): { code: number; stdout: string; stderr: string } {
  const proc = Bun.spawnSync(["bun", "run", CLI, ...args]);
  return {
    code: proc.exitCode,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

describe("cli.ts", () => {
  test("emits the resolved labels via the RESULT_LABELS marker", () => {
    writeFileSync(filesPath, "docs/readme.md\nsrc/api/users.test.ts\n");
    const { code, stdout } = runCli([configPath, filesPath]);
    expect(code).toBe(0);
    // api(10) before documentation/tests(0); within ties, alphabetical.
    expect(stdout).toContain("RESULT_LABELS=api,documentation,tests");
    expect(stdout).toContain("RESULT_COUNT=3");
  });

  test("emits an empty marker when no files match", () => {
    writeFileSync(filesPath, "LICENSE\nMakefile\n");
    const { code, stdout } = runCli([configPath, filesPath]);
    expect(code).toBe(0);
    expect(stdout).toContain("RESULT_LABELS=\n");
    expect(stdout).toContain("RESULT_COUNT=0");
  });

  test("exits non-zero with a clear message when the config is missing", () => {
    writeFileSync(filesPath, "docs/a.md\n");
    const { code, stderr } = runCli([join(dir, "missing.json"), filesPath]);
    expect(code).not.toBe(0);
    expect(stderr).toMatch(/config file not found/i);
  });

  test("exits non-zero with a clear message when the changed-files list is missing", () => {
    const { code, stderr } = runCli([configPath, join(dir, "missing.txt")]);
    expect(code).not.toBe(0);
    expect(stderr).toMatch(/changed-files list not found/i);
  });
});
