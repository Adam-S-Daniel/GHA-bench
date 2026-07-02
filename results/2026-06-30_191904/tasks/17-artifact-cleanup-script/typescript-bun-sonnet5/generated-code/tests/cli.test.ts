import { describe, expect, test } from "bun:test";
import { runCleanup } from "../src/cli";
import { makeArtifact } from "./helpers";

describe("runCleanup", () => {
  test("defaults to dry run and never calls deleteArtifact when DRY_RUN is unset", async () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = [
      makeArtifact({ id: "old", createdAt: new Date("2026-01-01T00:00:00Z") }),
      makeArtifact({ id: "new", createdAt: new Date("2026-06-30T00:00:00Z") }),
    ];
    const deletedIds: string[] = [];

    const { execution, report } = await runCleanup({
      env: { MAX_AGE_DAYS: "30" },
      now,
      artifacts,
      deleteArtifact: (a) => {
        deletedIds.push(a.id);
      },
    });

    expect(deletedIds).toEqual([]);
    expect(execution.dryRun).toBe(true);
    expect(execution.deletedIds).toEqual(["old"]);
    expect(report).toContain("Mode: DRY RUN (no artifacts deleted)");
    expect(report).toContain("[max-age] old");
  });

  test("deletes artifacts for real when DRY_RUN=false", async () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = [makeArtifact({ id: "old", createdAt: new Date("2026-01-01T00:00:00Z") })];
    const deletedIds: string[] = [];

    const { execution } = await runCleanup({
      env: { MAX_AGE_DAYS: "30", DRY_RUN: "false" },
      now,
      artifacts,
      deleteArtifact: (a) => {
        deletedIds.push(a.id);
      },
    });

    expect(deletedIds).toEqual(["old"]);
    expect(execution.dryRun).toBe(false);
    expect(execution.deletedIds).toEqual(["old"]);
  });

  test("surfaces invalid env configuration as a rejected promise with a clear message", async () => {
    const now = new Date("2026-07-01T00:00:00Z");

    await expect(
      runCleanup({
        env: { MAX_AGE_DAYS: "not-a-number" },
        now,
        artifacts: [],
        deleteArtifact: () => {},
      }),
    ).rejects.toThrow('MAX_AGE_DAYS must be a number, got "not-a-number"');
  });
});
