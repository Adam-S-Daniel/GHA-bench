import { describe, expect, test } from "bun:test";
import { buildCleanupPlan } from "./retention";
import type { Artifact } from "./types";

const NOW = new Date("2026-07-01T00:00:00.000Z");

function makeArtifact(overrides: Partial<Artifact>): Artifact {
  return {
    id: "1",
    name: "build-output",
    sizeBytes: 1000,
    createdAt: "2026-06-01T00:00:00.000Z",
    workflowRunId: "run-1",
    workflowName: "ci",
    ...overrides,
  };
}

describe("buildCleanupPlan - max age policy", () => {
  test("deletes artifacts older than maxAgeDays", () => {
    const old = makeArtifact({ id: "old", createdAt: "2026-05-01T00:00:00.000Z" });
    const fresh = makeArtifact({ id: "fresh", createdAt: "2026-06-30T00:00:00.000Z" });

    const plan = buildCleanupPlan([old, fresh], { maxAgeDays: 30 }, { now: NOW });

    expect(plan.toDelete.map((a) => a.id)).toEqual(["old"]);
    expect(plan.toRetain.map((a) => a.id)).toEqual(["fresh"]);
  });
});

describe("buildCleanupPlan - max total size policy", () => {
  test("evicts oldest artifacts first once total size exceeds the budget", () => {
    const a = makeArtifact({ id: "a", createdAt: "2026-06-01T00:00:00.000Z", sizeBytes: 500 });
    const b = makeArtifact({ id: "b", createdAt: "2026-06-15T00:00:00.000Z", sizeBytes: 500 });
    const c = makeArtifact({ id: "c", createdAt: "2026-06-30T00:00:00.000Z", sizeBytes: 500 });

    const plan = buildCleanupPlan([a, b, c], { maxTotalSizeBytes: 700 }, { now: NOW });

    // a is oldest, evicted first; then total would be 1000, still > 700 -> evict b too.
    expect(plan.toDelete.map((art) => art.id)).toEqual(["a", "b"]);
    expect(plan.toRetain.map((art) => art.id)).toEqual(["c"]);
    expect(plan.summary.spaceReclaimedBytes).toBe(1000);
  });
});

describe("buildCleanupPlan - keep latest N per workflow", () => {
  test("protects the N most recent artifacts of each workflow from other rules", () => {
    const old1 = makeArtifact({
      id: "old1",
      workflowName: "ci",
      createdAt: "2026-01-01T00:00:00.000Z",
    });
    const old2 = makeArtifact({
      id: "old2",
      workflowName: "ci",
      createdAt: "2026-01-02T00:00:00.000Z",
    });
    const other = makeArtifact({
      id: "other-wf",
      workflowName: "deploy",
      createdAt: "2026-01-03T00:00:00.000Z",
    });

    const plan = buildCleanupPlan(
      [old1, old2, other],
      { maxAgeDays: 1, keepLatestPerWorkflow: 1 },
      { now: NOW }
    );

    // Newest "ci" artifact (old2) is protected even though it's ancient by age.
    expect(plan.toRetain.map((a) => a.id).sort()).toEqual(["old2", "other-wf"]);
    expect(plan.toDelete.map((a) => a.id)).toEqual(["old1"]);
  });
});

describe("buildCleanupPlan - dry run mode", () => {
  test("computes the same plan but flags dryRun in the summary", () => {
    const old = makeArtifact({ id: "old", createdAt: "2026-05-01T00:00:00.000Z" });
    const plan = buildCleanupPlan([old], { maxAgeDays: 30 }, { now: NOW, dryRun: true });

    expect(plan.summary.dryRun).toBe(true);
    expect(plan.toDelete.map((a) => a.id)).toEqual(["old"]);
  });
});

describe("buildCleanupPlan - summary", () => {
  test("reports retained vs deleted counts and total space reclaimed", () => {
    const old = makeArtifact({ id: "old", createdAt: "2026-05-01T00:00:00.000Z", sizeBytes: 200 });
    const fresh = makeArtifact({ id: "fresh", createdAt: "2026-06-30T00:00:00.000Z", sizeBytes: 300 });

    const plan = buildCleanupPlan([old, fresh], { maxAgeDays: 30 }, { now: NOW });

    expect(plan.summary).toEqual({
      totalArtifacts: 2,
      retainedCount: 1,
      deletedCount: 1,
      spaceReclaimedBytes: 200,
      dryRun: false,
    });
  });
});

describe("buildCleanupPlan - input validation", () => {
  test("throws a meaningful error for a negative keepLatestPerWorkflow", () => {
    const a = makeArtifact({ id: "a" });
    expect(() =>
      buildCleanupPlan([a], { keepLatestPerWorkflow: -1 }, { now: NOW })
    ).toThrow(/keepLatestPerWorkflow/);
  });

  test("throws a meaningful error for a negative maxAgeDays", () => {
    const a = makeArtifact({ id: "a" });
    expect(() => buildCleanupPlan([a], { maxAgeDays: -5 }, { now: NOW })).toThrow(
      /maxAgeDays/
    );
  });

  test("throws a meaningful error for a negative maxTotalSizeBytes", () => {
    const a = makeArtifact({ id: "a" });
    expect(() =>
      buildCleanupPlan([a], { maxTotalSizeBytes: -1 }, { now: NOW })
    ).toThrow(/maxTotalSizeBytes/);
  });
});
