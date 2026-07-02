// RED/GREEN cycle 5: the CLI wiring, exercised as a real subprocess.
// Exit codes: 0 = report produced (no denied, or non-strict),
//             1 = denied licenses found under --strict,
//             2 = usage / input error.
import { describe, expect, test } from "bun:test";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const fixture = (name: string): string => join(root, "tests", "fixtures", name);

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Run the CLI with the given args and capture output. */
async function runCli(args: string[]): Promise<CliResult> {
  const proc = Bun.spawn(["bun", "run", join(root, "src", "cli.ts"), ...args], {
    cwd: root,
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

const baseArgs = [
  "--manifest", fixture("sample-package.json"),
  "--config", fixture("sample-config.json"),
  "--licenses", fixture("sample-license-db.json"),
];

describe("cli", () => {
  test("prints the exact compliance report and exits 0 without --strict", async () => {
    const { exitCode, stdout } = await runCli(baseArgs);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("APPROVED left-pad@^1.3.0 MIT");
    expect(stdout).toContain("DENIED evil-lib@2.0.0 GPL-3.0-only");
    expect(stdout).toContain("UNKNOWN typescript@~5.4.0 (license not found)");
    expect(stdout).toContain("Summary: total=3 approved=1 denied=1 unknown=1");
  });

  test("exits 1 under --strict when denied licenses are present", async () => {
    const { exitCode, stderr } = await runCli([...baseArgs, "--strict"]);
    expect(exitCode).toBe(1);
    expect(stderr).toContain("denied license(s) found");
  });

  test("exits 2 with a usage message when --manifest is missing", async () => {
    const { exitCode, stderr } = await runCli([]);
    expect(exitCode).toBe(2);
    expect(stderr).toContain("Usage:");
  });

  test("exits 2 with a meaningful error for a missing manifest file", async () => {
    const { exitCode, stderr } = await runCli([
      "--manifest", "/no/such/package.json",
      "--config", fixture("sample-config.json"),
      "--licenses", fixture("sample-license-db.json"),
    ]);
    expect(exitCode).toBe(2);
    expect(stderr).toContain("Manifest file not found");
  });
});
