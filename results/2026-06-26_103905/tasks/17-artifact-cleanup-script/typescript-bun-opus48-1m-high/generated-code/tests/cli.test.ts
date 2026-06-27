import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCleanup } from "../src/cli.ts";

// Temp dir for fixture files used by these CLI tests.
const dir = mkdtempSync(join(tmpdir(), "cleanup-cli-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

function fixtureFile(name: string, data: unknown): string {
  const path = join(dir, name);
  writeFileSync(path, JSON.stringify(data));
  return path;
}

const SAMPLE = {
  now: "2026-06-30T00:00:00Z",
  policy: { maxTotalSizeBytes: 1300 },
  artifacts: [
    { name: "old", sizeBytes: 600, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
    { name: "mid", sizeBytes: 600, createdAt: "2026-06-10T00:00:00Z", workflowRunId: 1 },
    { name: "new", sizeBytes: 600, createdAt: "2026-06-20T00:00:00Z", workflowRunId: 1 },
  ],
};

describe("runCleanup", () => {
  test("reads a fixture file given via --fixture and prints a dry-run plan", () => {
    const path = fixtureFile("sample.json", SAMPLE);
    const result = runCleanup(["--fixture", path, "--dry-run"]);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Mode: DRY-RUN");
    expect(result.stdout).toContain("Deleted: 1");
    expect(result.stdout).toContain("Space reclaimed: 600 bytes");
    expect(result.stderr).toBe("");
  });

  test("honours the FIXTURE_FILE env var when no --fixture flag is given", () => {
    const path = fixtureFile("env.json", SAMPLE);
    const result = runCleanup([], { FIXTURE_FILE: path, DRY_RUN: "true" });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Deleted: 1");
  });

  test("defaults to live mode (no DRY-RUN flag) and reports the deletion", () => {
    const path = fixtureFile("live.json", SAMPLE);
    const result = runCleanup(["--fixture", path]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Mode: LIVE");
    expect(result.stdout).toContain("LIVE: deleted 1 artifact(s), reclaiming 600 bytes.");
  });

  test("exits non-zero with a clear message when no fixture is provided", () => {
    const result = runCleanup([]);
    expect(result.exitCode).toBe(2);
    expect(result.stderr).toMatch(/no fixture/i);
  });

  test("exits non-zero with a clear message when the fixture file is missing", () => {
    const result = runCleanup(["--fixture", join(dir, "does-not-exist.json")]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toMatch(/could not read fixture/i);
  });

  test("exits non-zero with a clear message on invalid JSON", () => {
    const path = join(dir, "bad.json");
    writeFileSync(path, "{ not valid json ");
    const result = runCleanup(["--fixture", path]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toMatch(/invalid json/i);
  });

  test("exits non-zero with a validation message on a bad artifact", () => {
    const path = fixtureFile("badart.json", {
      artifacts: [{ name: "x", sizeBytes: -1, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 }],
    });
    const result = runCleanup(["--fixture", path]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toMatch(/sizeBytes.*non-negative/i);
  });
});
