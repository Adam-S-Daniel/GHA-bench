/**
 * End-to-end CLI tests (RED first: src/cli.ts does not exist).
 *
 * Approach: spawn `bun run src/cli.ts` exactly as CI does, feed it the
 * committed fixtures (manifest + allow/deny config + mock license database),
 * and assert on the exact rendered report, stderr, and exit codes.
 */
import { describe, expect, test } from "bun:test";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const FIXTURES = join(ROOT, "tests", "fixtures");

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

async function runCli(...args: string[]): Promise<CliResult> {
  const proc = Bun.spawn(["bun", "run", join(ROOT, "src", "cli.ts"), ...args], {
    cwd: ROOT,
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

const npmArgs = [
  "--manifest", join(FIXTURES, "npm", "package.json"),
  "--config", join(FIXTURES, "license-config.json"),
  "--licenses", join(FIXTURES, "licenses.json"),
];

describe("cli", () => {
  test("reports npm manifest compliance with exact output and exit 0", async () => {
    const { exitCode, stdout } = await runCli(...npmArgs);
    expect(stdout).toBe(
      [
        "License Compliance Report",
        "=========================",
        "left-pad@1.3.0: GPL-3.0 [denied]",
        "mystery-lib@0.0.1: UNKNOWN [unknown]",
        "react@18.2.0: MIT [approved]",
        "typescript@5.4.0: Apache-2.0 [approved]",
        "Summary: 2 approved, 1 denied, 1 unknown",
        "",
      ].join("\n"),
    );
    expect(exitCode).toBe(0);
  });

  test("reports requirements.txt compliance with exact output", async () => {
    const { exitCode, stdout } = await runCli(
      "--manifest", join(FIXTURES, "pip", "requirements.txt"),
      "--config", join(FIXTURES, "license-config.json"),
      "--licenses", join(FIXTURES, "licenses.json"),
    );
    expect(stdout).toBe(
      [
        "License Compliance Report",
        "=========================",
        "copyleft-tool@1.0.0: AGPL-3.0 [denied]",
        "flask@3.0.1: BSD-3-Clause [approved]",
        "numpy@*: UNKNOWN [unknown]",
        "requests@2.31.0: Apache-2.0 [approved]",
        "Summary: 2 approved, 1 denied, 1 unknown",
        "",
      ].join("\n"),
    );
    expect(exitCode).toBe(0);
  });

  test("--strict exits 2 when any dependency is denied", async () => {
    const { exitCode, stderr } = await runCli(...npmArgs, "--strict");
    expect(exitCode).toBe(2);
    expect(stderr).toContain("1 denied license(s) found");
  });

  test("fails with a meaningful error when the manifest is missing", async () => {
    const { exitCode, stderr } = await runCli(
      "--manifest", "/no/such/package.json",
      "--config", join(FIXTURES, "license-config.json"),
      "--licenses", join(FIXTURES, "licenses.json"),
    );
    expect(exitCode).toBe(1);
    expect(stderr).toContain("Manifest file not found: /no/such/package.json");
  });

  test("fails with usage help when required flags are missing", async () => {
    const { exitCode, stderr } = await runCli();
    expect(exitCode).toBe(1);
    expect(stderr).toContain("Missing required option: --manifest");
    expect(stderr).toContain("Usage:");
  });

  test("fails with a meaningful error when config lists are malformed", async () => {
    const badConfig = join(FIXTURES, "npm", "package.json"); // valid JSON, wrong shape
    const { exitCode, stderr } = await runCli(
      "--manifest", join(FIXTURES, "npm", "package.json"),
      "--config", badConfig,
      "--licenses", join(FIXTURES, "licenses.json"),
    );
    expect(exitCode).toBe(1);
    expect(stderr).toContain('"allow" must be an array of license strings');
  });
});
