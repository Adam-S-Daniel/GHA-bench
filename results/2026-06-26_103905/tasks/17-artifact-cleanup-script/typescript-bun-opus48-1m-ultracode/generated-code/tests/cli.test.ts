import { describe, test, expect } from "bun:test";

/**
 * These tests drive the CLI as a real subprocess (`bun run artifact-cleanup.ts`)
 * to exercise argv parsing, file I/O and exit codes end-to-end — the same path
 * the GitHub Actions workflow takes.
 */

const SCRIPT = "artifact-cleanup.ts";

function runCli(args: string[]): { code: number; stdout: string; stderr: string } {
  const proc = Bun.spawnSync(["bun", "run", SCRIPT, ...args]);
  return {
    code: proc.exitCode,
    stdout: proc.stdout.toString(),
    stderr: proc.stderr.toString(),
  };
}

describe("CLI — happy path", () => {
  test("processes the basic fixture and prints the exact SUMMARY line", () => {
    const { code, stdout } = runCli(["fixtures/basic.json", "--dry-run"]);
    expect(code).toBe(0);
    expect(stdout).toContain("Mode: DRY-RUN");
    expect(stdout).toContain(
      "SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=8000 retained_bytes=3000 total_bytes=11000",
    );
  });

  test("size-pressure fixture deletes the single oldest artifact", () => {
    const { code, stdout } = runCli(["fixtures/size-pressure.json", "--dry-run"]);
    expect(code).toBe(0);
    expect(stdout).toContain(
      "SUMMARY total=3 retained=2 deleted=1 reclaimed_bytes=4000 retained_bytes=8000 total_bytes=12000",
    );
  });

  test("keep-n fixture keeps the 2 newest of 4", () => {
    const { code, stdout } = runCli(["fixtures/keep-n.json", "--dry-run"]);
    expect(code).toBe(0);
    expect(stdout).toContain(
      "SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=200 retained_bytes=200 total_bytes=400",
    );
  });

  test("all-fresh fixture deletes nothing", () => {
    const { code, stdout } = runCli(["fixtures/all-fresh.json"]);
    expect(code).toBe(0);
    expect(stdout).toContain("Mode: EXECUTE");
    expect(stdout).toContain(
      "SUMMARY total=2 retained=2 deleted=0 reclaimed_bytes=0 retained_bytes=3000 total_bytes=3000",
    );
  });
});

describe("CLI — JSON output", () => {
  test("--format json emits valid JSON with the summary", () => {
    const { code, stdout } = runCli(["fixtures/basic.json", "--dry-run", "--format", "json"]);
    expect(code).toBe(0);
    const parsed = JSON.parse(stdout) as { summary: { deletedCount: number } };
    expect(parsed.summary.deletedCount).toBe(2);
  });
});

describe("CLI — policy overrides", () => {
  test("--keep-latest overrides the fixture policy", () => {
    // keep-n fixture has 4 artifacts in one workflow; keeping 1 deletes 3.
    const { code, stdout } = runCli(["fixtures/keep-n.json", "--keep-latest", "1", "--dry-run"]);
    expect(code).toBe(0);
    expect(stdout).toContain(
      "SUMMARY total=4 retained=1 deleted=3 reclaimed_bytes=300 retained_bytes=100 total_bytes=400",
    );
  });
});

describe("CLI — error handling", () => {
  test("missing config path exits non-zero with a helpful message", () => {
    const { code, stderr } = runCli([]);
    expect(code).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("usage");
  });

  test("non-existent config file exits non-zero", () => {
    const { code, stderr } = runCli(["does-not-exist.json"]);
    expect(code).not.toBe(0);
    expect(stderr.toLowerCase()).toContain("error");
  });

  test("malformed policy (negative maxAgeDays) is reported", () => {
    const { code, stderr } = runCli(["fixtures/basic.json", "--max-age-days", "-5"]);
    expect(code).not.toBe(0);
    expect(stderr).toContain("maxAgeDays");
  });

  test("--help prints usage and exits 0", () => {
    const { code, stdout } = runCli(["--help"]);
    expect(code).toBe(0);
    expect(stdout.toLowerCase()).toContain("usage");
  });
});
