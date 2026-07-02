import { describe, expect, test } from "bun:test";
import { join } from "node:path";

/**
 * End-to-end tests for the CLI: spawn `bun run src/cli.ts` exactly the way the
 * GitHub Actions workflow does, and assert on exit code + output. The CLI
 * prints a human-readable report plus a machine-readable JSON plan wrapped in
 * ::PLAN::...::ENDPLAN:: markers (that marker line is what the act harness
 * parses out of CI logs).
 */

const ROOT = join(import.meta.dir, "..");
const CLI = join(ROOT, "src", "cli.ts");
const fixture = (name: string): string => join(import.meta.dir, "fixtures", name);

interface CliResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

async function runCli(args: string[]): Promise<CliResult> {
  const proc = Bun.spawn(["bun", "run", CLI, ...args], {
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

/** Extracts and parses the machine-readable plan from CLI output. */
function extractPlan(stdout: string): any {
  const match = stdout.match(/::PLAN::(.*)::ENDPLAN::/);
  expect(match).not.toBeNull();
  return JSON.parse(match![1]!);
}

describe("cli", () => {
  test("dry-run: prints exact summary and a parseable plan, deletes nothing", async () => {
    const { exitCode, stdout } = await runCli([
      "--artifacts", fixture("artifacts.combined.json"),
      "--config", fixture("policy.dryrun.json"),
    ]);

    expect(exitCode).toBe(0);
    expect(stdout).toContain("Artifact Cleanup Plan (DRY RUN)");
    expect(stdout).toContain(
      "Summary: 6 total | 3 retained (210 bytes) | 3 to delete | 350 bytes reclaimed",
    );
    // Dry-run must not print any DELETED lines.
    expect(stdout).not.toContain("DELETED ");

    const plan = extractPlan(stdout);
    expect(plan.summary).toEqual({
      totalArtifacts: 6,
      retainedCount: 3,
      deletedCount: 3,
      spaceReclaimedBytes: 350,
      retainedSizeBytes: 210,
    });
    expect(plan.dryRun).toBe(true);
    expect(plan.toDelete.map((a: any) => a.name).sort()).toEqual(["A1", "A2", "A5"]);
    expect(plan.toRetain.map((a: any) => a.name).sort()).toEqual(["A3", "A4", "A6"]);
  });

  test("execute mode: prints a DELETED line per doomed artifact", async () => {
    const { exitCode, stdout } = await runCli([
      "--artifacts", fixture("artifacts.combined.json"),
      "--config", fixture("policy.execute.json"),
    ]);

    expect(exitCode).toBe(0);
    expect(stdout).toContain("DELETED A1 (id=1, 100 bytes)");
    expect(stdout).toContain("DELETED A2 (id=2, 50 bytes)");
    expect(stdout).toContain("DELETED A5 (id=5, 200 bytes)");
    expect(stdout).toContain("Deleted 3 artifacts, reclaimed 350 bytes");
  });

  test("--dry-run flag overrides dryRun:false in the config", async () => {
    const { exitCode, stdout } = await runCli([
      "--artifacts", fixture("artifacts.combined.json"),
      "--config", fixture("policy.execute.json"),
      "--dry-run",
    ]);

    expect(exitCode).toBe(0);
    expect(stdout).toContain("Artifact Cleanup Plan (DRY RUN)");
    expect(stdout).not.toContain("DELETED ");
  });

  test("missing artifacts file exits 1 with a helpful error", async () => {
    const { exitCode, stderr } = await runCli([
      "--artifacts", fixture("does-not-exist.json"),
      "--config", fixture("policy.dryrun.json"),
    ]);

    expect(exitCode).toBe(1);
    expect(stderr).toContain("error: cannot read artifacts file");
    expect(stderr).toContain("does-not-exist.json");
  });

  test("malformed artifacts JSON exits 1 with a parse error", async () => {
    const { exitCode, stderr } = await runCli([
      "--artifacts", fixture("artifacts.malformed.json"),
      "--config", fixture("policy.dryrun.json"),
    ]);

    expect(exitCode).toBe(1);
    expect(stderr).toContain("error: artifacts JSON is invalid JSON");
  });

  test("missing required flag exits 1 with usage", async () => {
    const { exitCode, stderr } = await runCli(["--config", fixture("policy.dryrun.json")]);

    expect(exitCode).toBe(1);
    expect(stderr).toContain("error: --artifacts <file> is required");
    expect(stderr).toContain("Usage:");
  });
});
