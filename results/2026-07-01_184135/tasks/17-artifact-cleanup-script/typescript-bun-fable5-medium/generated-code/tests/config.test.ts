/**
 * Tests for JSON config loading — written first (red/green TDD).
 * Fixtures are written to a temp directory per test run.
 */
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadArtifactsFile, loadPolicyFile } from "../src/config.ts";

const dir: string = mkdtempSync(join(tmpdir(), "cleanup-config-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

/** Write a fixture file and return its path. */
function fixture(name: string, content: string): string {
  const path = join(dir, name);
  writeFileSync(path, content);
  return path;
}

describe("loadArtifactsFile", () => {
  test("parses a valid artifacts array", async () => {
    const path = fixture(
      "good-artifacts.json",
      JSON.stringify([
        {
          name: "a",
          sizeBytes: 10,
          createdAt: "2026-06-29T00:00:00Z",
          workflowRunId: 1,
        },
      ]),
    );
    const artifacts = await loadArtifactsFile(path);
    expect(artifacts).toHaveLength(1);
    expect(artifacts[0]?.name).toBe("a");
  });

  test("fails with a meaningful error for a missing file", async () => {
    await expect(loadArtifactsFile(join(dir, "nope.json"))).rejects.toThrow(
      /cannot read artifacts file/,
    );
  });

  test("fails when the JSON is not an array", async () => {
    const path = fixture("not-array.json", "{}");
    await expect(loadArtifactsFile(path)).rejects.toThrow(
      /must contain a JSON array/,
    );
  });

  test("fails when an entry is missing a required field", async () => {
    const path = fixture(
      "missing-field.json",
      JSON.stringify([{ name: "a", sizeBytes: 10, createdAt: "2026-06-29T00:00:00Z" }]),
    );
    await expect(loadArtifactsFile(path)).rejects.toThrow(
      /artifact at index 0: "workflowRunId" must be a number/,
    );
  });
});

describe("loadPolicyFile", () => {
  test("parses a valid policy with all fields", async () => {
    const path = fixture(
      "good-policy.json",
      JSON.stringify({
        maxAgeDays: 30,
        keepLatestPerWorkflow: 2,
        maxTotalSizeBytes: 209715200,
        dryRun: true,
      }),
    );
    const policy = await loadPolicyFile(path);
    expect(policy).toEqual({
      maxAgeDays: 30,
      keepLatestPerWorkflow: 2,
      maxTotalSizeBytes: 209715200,
      dryRun: true,
    });
  });

  test("omitted fields stay undefined (rule skipped)", async () => {
    const path = fixture("sparse-policy.json", JSON.stringify({ maxAgeDays: 7 }));
    const policy = await loadPolicyFile(path);
    expect(policy.maxAgeDays).toBe(7);
    expect(policy.keepLatestPerWorkflow).toBeUndefined();
    expect(policy.maxTotalSizeBytes).toBeUndefined();
  });

  test("fails on malformed JSON with a meaningful error", async () => {
    const path = fixture("bad.json", "{ nope");
    await expect(loadPolicyFile(path)).rejects.toThrow(/invalid JSON/);
  });

  test("fails on wrong field types", async () => {
    const path = fixture(
      "bad-type.json",
      JSON.stringify({ maxAgeDays: "thirty" }),
    );
    await expect(loadPolicyFile(path)).rejects.toThrow(
      /"maxAgeDays" must be a number/,
    );
  });
});
