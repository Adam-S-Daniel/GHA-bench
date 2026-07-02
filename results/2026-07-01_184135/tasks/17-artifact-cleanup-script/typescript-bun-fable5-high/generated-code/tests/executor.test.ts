import { describe, expect, test } from "bun:test";
import { executePlan, type ArtifactDeleter } from "../src/executor";
import { buildDeletionPlan } from "../src/planner";
import type { Artifact } from "../src/types";

const NOW = new Date("2026-07-01T00:00:00Z");

const artifacts: Artifact[] = [
  { id: 1, name: "stale-a", sizeBytes: 10, createdAt: "2026-01-01T00:00:00Z", workflowRunId: 1 },
  { id: 2, name: "stale-b", sizeBytes: 20, createdAt: "2026-02-01T00:00:00Z", workflowRunId: 2 },
  { id: 3, name: "fresh", sizeBytes: 30, createdAt: "2026-06-30T00:00:00Z", workflowRunId: 3 },
];

/** Mock deleter that records which artifact ids it was asked to delete. */
function recordingDeleter(): { deleter: ArtifactDeleter; deletedIds: number[] } {
  const deletedIds: number[] = [];
  return {
    deletedIds,
    deleter: async (artifact) => {
      deletedIds.push(artifact.id);
    },
  };
}

describe("executePlan", () => {
  test("dry-run never invokes the deleter but still reports what it would do", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 30 }, { referenceDate: NOW, dryRun: true });
    const { deleter, deletedIds } = recordingDeleter();

    const result = await executePlan(plan, deleter);

    expect(deletedIds).toEqual([]);
    expect(result.deleted.map((a) => a.name)).toEqual([]);
    expect(result.skippedDryRun.map((a) => a.name)).toEqual(["stale-a", "stale-b"]);
  });

  test("execute mode deletes exactly the doomed artifacts, in plan order", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 30 }, { referenceDate: NOW });
    const { deleter, deletedIds } = recordingDeleter();

    const result = await executePlan(plan, deleter);

    expect(deletedIds).toEqual([1, 2]);
    expect(result.deleted.map((a) => a.name)).toEqual(["stale-a", "stale-b"]);
    expect(result.skippedDryRun).toEqual([]);
  });

  test("a deleter failure is wrapped with the artifact identity", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 30 }, { referenceDate: NOW });
    const failing: ArtifactDeleter = async (artifact) => {
      if (artifact.id === 2) throw new Error("HTTP 500");
    };

    await expect(executePlan(plan, failing)).rejects.toThrow(
      'failed to delete artifact "stale-b" (id=2): HTTP 500',
    );
  });
});
