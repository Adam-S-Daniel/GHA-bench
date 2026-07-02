// TDD iteration 6 (RED): the CLI. The GitHub Actions workflow invokes
//   bun run src/cli.ts --config <rules.json> --files <changed-files.json>
// so these tests spawn the real process and assert on its observable
// contract: stdout format, stderr messages, and exit codes.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CLI = join(import.meta.dir, "cli.ts");
const FIXTURES = join(import.meta.dir, "..", "fixtures");

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Run the CLI as a real subprocess, exactly as CI does. */
function runCli(args: string[]): CliResult {
  const proc = Bun.spawnSync(["bun", "run", CLI, ...args]);
  return {
    exitCode: proc.exitCode,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

/** Write throwaway fixture files for a single test. */
function tempFixture(name: string, content: string): string {
  const dir = mkdtempSync(join(tmpdir(), "labeler-"));
  const path = join(dir, name);
  writeFileSync(path, content);
  return path;
}

describe("cli: happy path", () => {
  test("computes labels from the checked-in fixtures with exact output", () => {
    const result = runCli([
      "--config", join(FIXTURES, "rules.json"),
      "--files", join(FIXTURES, "changed-files.json"),
    ]);
    expect(result.stderr).toBe("");
    expect(result.exitCode).toBe(0);
    // docs/intro.md → documentation; docs/api/rest.md → api-docs (priority 10
    // suppresses docs/**); src/api/users.ts → api, backend;
    // src/api/users.test.ts → api, backend, tests; README.md → nothing.
    expect(result.stdout).toContain(
      "FINAL LABELS: api,api-docs,backend,documentation,tests",
    );
  });

  test("prints a stable sentinel when nothing matches", () => {
    const files = tempFixture("files.json", '["LICENSE"]');
    const result = runCli([
      "--config", join(FIXTURES, "rules.json"),
      "--files", files,
    ]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("FINAL LABELS: (none)");
  });
});

describe("cli: error handling", () => {
  test("missing required arguments → usage message, exit 1", () => {
    const result = runCli([]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Usage:");
  });

  test("nonexistent config file → meaningful error, exit 1", () => {
    const result = runCli([
      "--config", "/no/such/rules.json",
      "--files", join(FIXTURES, "changed-files.json"),
    ]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("/no/such/rules.json");
  });

  test("invalid rules JSON → validation error naming the problem, exit 1", () => {
    const config = tempFixture("rules.json", '{"rules": [{"labels": ["x"]}]}');
    const result = runCli([
      "--config", config,
      "--files", join(FIXTURES, "changed-files.json"),
    ]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain('rules[0] is missing a non-empty string "pattern"');
  });
});
