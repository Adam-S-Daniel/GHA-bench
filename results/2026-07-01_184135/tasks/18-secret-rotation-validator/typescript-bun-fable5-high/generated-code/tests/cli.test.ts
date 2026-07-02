/**
 * TDD Cycle 5: CLI integration.
 *
 * These tests spawn the real CLI (`bun run src/cli.ts`) against the JSON
 * fixtures in fixtures/, exactly as the GitHub Actions workflow does, and
 * assert on exit codes, stdout, and stderr.
 */
import { describe, expect, test } from "bun:test";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Run the CLI with the given args and capture everything. */
function runCli(...args: string[]): CliResult {
  const proc = Bun.spawnSync(["bun", "run", "src/cli.ts", ...args], {
    cwd: ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    exitCode: proc.exitCode,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

const MIXED = ["--config", "fixtures/mixed-secrets.json", "--now", "2026-07-02"];

describe("cli", () => {
  test("markdown is the default format and groups by urgency", () => {
    const { exitCode, stdout } = runCli(...MIXED);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("# Secret Rotation Report");
    expect(stdout).toContain("## EXPIRED (2)");
    expect(stdout).toContain("## WARNING (1)");
    expect(stdout).toContain("## OK (1)");
    expect(stdout).toContain(
      "| db-password | 2026-01-01 | 90 | 2026-04-01 | -92 | auth-service, billing-api |",
    );
  });

  test("--format json emits the machine-readable report", () => {
    const { exitCode, stdout } = runCli(...MIXED, "--format", "json");
    expect(exitCode).toBe(0);
    const report = JSON.parse(stdout);
    expect(report.summary).toEqual({ expired: 2, warning: 1, ok: 1 });
    expect(report.groups.warning[0].secret.name).toBe("api-key-stripe");
  });

  test("--window changes the warning cutoff", () => {
    // With a 5-day window, api-key-stripe (8 days out) becomes ok.
    const { exitCode, stdout } = runCli(...MIXED, "--window", "5", "--format", "json");
    expect(exitCode).toBe(0);
    expect(JSON.parse(stdout).summary).toEqual({ expired: 2, warning: 0, ok: 2 });
  });

  test("fails with the validation message on an invalid config", () => {
    const { exitCode, stderr } = runCli(
      "--config",
      "fixtures/invalid-secrets.json",
      "--now",
      "2026-07-02",
    );
    expect(exitCode).toBe(1);
    expect(stderr).toContain(
      'Error: secret at index 0: "name" must be a non-empty string',
    );
  });

  test("fails helpfully when the config file does not exist", () => {
    const { exitCode, stderr } = runCli("--config", "no/such/file.json");
    expect(exitCode).toBe(1);
    expect(stderr).toContain("cannot read config file");
    expect(stderr).toContain("no/such/file.json");
  });

  test("fails helpfully on unknown flags and on a missing --config", () => {
    expect(runCli(...MIXED, "--frmat", "json").stderr).toContain(
      'unknown option "--frmat"',
    );
    expect(runCli().stderr).toContain("missing required option --config");
  });

  test("rejects a non-numeric --window", () => {
    const { exitCode, stderr } = runCli(...MIXED, "--window", "soon");
    expect(exitCode).toBe(1);
    expect(stderr).toContain("--window must be a positive integer");
  });
});
