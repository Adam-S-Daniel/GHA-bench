import { describe, expect, test } from "bun:test";
import { executeCleanupPlan } from "../src/executor";
import type { CleanupPlan } from "../src/types";
import { makeArtifact } from "./helpers";

function makePlan(): CleanupPlan {
  const kept = makeArtifact({ id: "kept" });
  const doomed1 = makeArtifact({ id: "doomed-1" });
  const doomed2 = makeArtifact({ id: "doomed-2" });
  return {
    retained: [kept],
    deletions: [
      { artifact: doomed1, reason: "max-age" },
      { artifact: doomed2, reason: "keep-latest-n" },
    ],
    summary: {
      totalArtifacts: 3,
      retainedCount: 1,
      deletedCount: 2,
      totalSizeInBytes: 3072,
      retainedSizeInBytes: 1024,
      reclaimedSizeInBytes: 2048,
      deletedByReason: { "max-age": 1, "keep-latest-n": 1, "max-total-size": 0 },
    },
  };
}

describe("executeCleanupPlan", () => {
  test("dry run never invokes the delete callback", async () => {
    const deletedIds: string[] = [];
    const result = await executeCleanupPlan(makePlan(), async (artifact) => {
      deletedIds.push(artifact.id);
    }, { dryRun: true });

    expect(deletedIds).toEqual([]);
    expect(result.dryRun).toBe(true);
    expect(result.deletedIds.sort()).toEqual(["doomed-1", "doomed-2"]);
    expect(result.failures).toEqual([]);
  });

  test("wet run invokes the delete callback for every planned deletion", async () => {
    const deletedIds: string[] = [];
    const result = await executeCleanupPlan(makePlan(), async (artifact) => {
      deletedIds.push(artifact.id);
    }, { dryRun: false });

    expect(deletedIds.sort()).toEqual(["doomed-1", "doomed-2"]);
    expect(result.dryRun).toBe(false);
    expect(result.deletedIds.sort()).toEqual(["doomed-1", "doomed-2"]);
    expect(result.failures).toEqual([]);
  });

  test("collects per-artifact failures instead of aborting the whole run", async () => {
    const result = await executeCleanupPlan(
      makePlan(),
      async (artifact) => {
        if (artifact.id === "doomed-1") {
          throw new Error("simulated network error");
        }
      },
      { dryRun: false },
    );

    expect(result.deletedIds).toEqual(["doomed-2"]);
    expect(result.failures).toEqual([
      { artifactId: "doomed-1", message: "simulated network error" },
    ]);
  });
});
