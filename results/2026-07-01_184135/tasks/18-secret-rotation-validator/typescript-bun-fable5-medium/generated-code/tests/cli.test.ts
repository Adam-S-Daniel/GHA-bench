// RED/GREEN cycle 5: the CLI entry point.
//
// runCli is a pure function (args in, {exitCode, stdout, stderr} out) so we
// can test flag parsing, format selection, and error handling without
// spawning subprocesses. src/cli.ts is a thin wrapper that wires it to
// process.argv / process.exit.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCli } from "../src/cli";

const dir = mkdtempSync(join(tmpdir(), "rotation-cli-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const CONFIG = join(dir, "secrets.json");
writeFileSync(
  CONFIG,
  JSON.stringify({
    secrets: [
      { name: "api-key", lastRotated: "2026-06-01", rotationPolicyDays: 90, requiredBy: ["api"] },
      { name: "db-password", lastRotated: "2026-03-01", rotationPolicyDays: 90, requiredBy: ["api", "worker"] },
      { name: "tls-cert", lastRotated: "2026-04-09", rotationPolicyDays: 90, requiredBy: ["gateway"] },
    ],
  }),
);

const BASE_ARGS = ["--config", CONFIG, "--now", "2026-07-01", "--warning-days", "14"];

describe("runCli", () => {
  test("default markdown output includes the summary line", () => {
    const result = runCli(BASE_ARGS);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("**Summary:** 1 expired, 1 warning, 1 ok");
    expect(result.stderr).toBe("");
  });

  test("--format json emits parseable JSON with grouped notifications", () => {
    const result = runCli([...BASE_ARGS, "--format", "json"]);
    expect(result.exitCode).toBe(0);
    const parsed = JSON.parse(result.stdout);
    expect(parsed.summary).toEqual({ expired: 1, warning: 1, ok: 1 });
    expect(parsed.notifications.expired[0].name).toBe("db-password");
  });

  test("--fail-on-expired exits 2 when any secret is expired", () => {
    const result = runCli([...BASE_ARGS, "--fail-on-expired"]);
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("1 secret(s) are expired");
  });

  test("missing config file exits 1 with the loader's message", () => {
    const result = runCli(["--config", join(dir, "absent.json")]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Configuration file not found:");
  });

  test("unknown flag exits 1 with usage help", () => {
    const result = runCli([...BASE_ARGS, "--bogus"]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Unknown option: --bogus");
    expect(result.stderr).toContain("Usage:");
  });

  test("invalid --format exits 1 with the allowed values", () => {
    const result = runCli([...BASE_ARGS, "--format", "xml"]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain('Invalid --format "xml" (expected "markdown" or "json")');
  });

  test("invalid --now exits 1 with a clear message", () => {
    const result = runCli(["--config", CONFIG, "--now", "yesterday"]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain('Invalid --now date: "yesterday" (expected YYYY-MM-DD)');
  });
});
