import { describe, expect, test } from "bun:test";

// RED: fails until src/cli.ts exists and behaves as asserted below.
// This spawns the real CLI as a subprocess (not through act -- that's covered
// separately by the GitHub Actions pipeline tests) to verify argument parsing,
// output formatting, and exit codes end-to-end.
function runCli(args: string[]): { stdout: string; stderr: string; exitCode: number } {
  const proc = Bun.spawnSync(["bun", "run", "src/cli.ts", ...args], {
    cwd: import.meta.dir + "/..",
  });
  return {
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
    exitCode: proc.exitCode ?? -1,
  };
}

describe("CLI", () => {
  test("prints a compliance report and exits 0 for a valid manifest", () => {
    const result = runCli([
      "--manifest",
      "tests/fixtures/cli-scenario/package.json",
      "--config",
      "tests/fixtures/cli-scenario/license-policy.json",
      "--lookup",
      "tests/fixtures/cli-scenario/license-data.json",
    ]);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("[APPROVED] left-pad@1.3.0 - MIT");
    expect(result.stdout).toContain("[DENIED] old-gpl-lib@2.0.0 - GPL-3.0");
    expect(result.stdout).toContain("[UNKNOWN] mystery-pkg@0.1.0 - UNKNOWN");
    expect(result.stdout).toContain("SUMMARY: total=3 approved=1 denied=1 unknown=1");
  });

  test("exits 1 with a clear stderr message for a missing manifest", () => {
    const result = runCli([
      "--manifest",
      "tests/fixtures/does-not-exist/package.json",
      "--config",
      "tests/fixtures/cli-scenario/license-policy.json",
      "--lookup",
      "tests/fixtures/cli-scenario/license-data.json",
    ]);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Error:");
    expect(result.stderr).toMatch(/not found/i);
  });

  test("exits 1 with a clear stderr message for an invalid license policy file", () => {
    const result = runCli([
      "--manifest",
      "tests/fixtures/cli-scenario/package.json",
      "--config",
      "tests/fixtures/license-policy.invalid.json",
      "--lookup",
      "tests/fixtures/cli-scenario/license-data.json",
    ]);

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Error:");
    expect(result.stderr).toMatch(/allowlist/i);
  });
});
