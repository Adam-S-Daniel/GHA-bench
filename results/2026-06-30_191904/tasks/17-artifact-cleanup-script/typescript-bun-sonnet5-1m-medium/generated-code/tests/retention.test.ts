import { describe, test, expect } from "bun:test";
import type { Artifact, RetentionPolicy } from "../src/types";
import { buildDeletionPlan, summarizePlan } from "../src/retention";

// Fixed "now" so tests are deterministic regardless of wall-clock time.
const NOW = new Date("2026-07-01T00:00:00.000Z");

function makeArtifact(overrides: Partial<Artifact>): Artifact {
  return {
    id: "art-1",
    name: "build-output",
    sizeInBytes: 1000,
    createdAt: "2026-07-01T00:00:00.000Z",
    workflowRunId: "run-1",
    workflowName: "ci",
    ...overrides,
  };
}

describe("buildDeletionPlan - maxAgeDays policy", () => {
  test("marks artifacts older than maxAgeDays for deletion", () => {
    const oldArtifact = makeArtifact({
      id: "old",
      createdAt: "2026-06-01T00:00:00.000Z", // 30 days before NOW
    });
    const freshArtifact = makeArtifact({
      id: "fresh",
      createdAt: "2026-06-30T00:00:00.000Z", // 1 day before NOW
    });
    const policy: RetentionPolicy = { maxAgeDays: 7 };

    const plan = buildDeletionPlan([oldArtifact, freshArtifact], policy, {
      now: NOW,
      dryRun: true,
    });

    expect(plan.toDelete.map((d) => d.artifact.id)).toEqual(["old"]);
    expect(plan.toRetain.map((d) => d.artifact.id)).toEqual(["fresh"]);
  });
});

describe("buildDeletionPlan - maxTotalSizeBytes policy", () => {
  test("deletes oldest artifacts first until total size is under the cap", () => {
    // Three same-workflow artifacts, 500 bytes each, all fresh (no age violation).
    // Cap is 1000 bytes, so the single oldest artifact must go to get under cap.
    const artifacts: Artifact[] = [
      makeArtifact({
        id: "oldest",
        createdAt: "2026-06-29T00:00:00.000Z",
        sizeInBytes: 500,
      }),
      makeArtifact({
        id: "middle",
        createdAt: "2026-06-30T00:00:00.000Z",
        sizeInBytes: 500,
      }),
      makeArtifact({
        id: "newest",
        createdAt: "2026-06-30T12:00:00.000Z",
        sizeInBytes: 500,
      }),
    ];
    const policy: RetentionPolicy = { maxTotalSizeBytes: 1000 };

    const plan = buildDeletionPlan(artifacts, policy, { now: NOW, dryRun: true });

    expect(plan.toDelete.map((d) => d.artifact.id)).toEqual(["oldest"]);
    expect(plan.toRetain.map((d) => d.artifact.id).sort()).toEqual([
      "middle",
      "newest",
    ]);
    expect(plan.totalBytesReclaimed).toBe(500);
  });
});

describe("buildDeletionPlan - keepLatestPerWorkflow policy", () => {
  test("protects the N most recent artifacts per workflow even if they violate maxAgeDays", () => {
    // All three artifacts are old enough to violate maxAgeDays, but
    // keepLatestPerWorkflow=1 should protect the single newest one per workflow.
    const artifacts: Artifact[] = [
      makeArtifact({
        id: "ci-old",
        workflowName: "ci",
        createdAt: "2026-06-01T00:00:00.000Z",
      }),
      makeArtifact({
        id: "ci-newest",
        workflowName: "ci",
        createdAt: "2026-06-10T00:00:00.000Z",
      }),
      makeArtifact({
        id: "deploy-old",
        workflowName: "deploy",
        createdAt: "2026-06-01T00:00:00.000Z",
      }),
      makeArtifact({
        id: "deploy-newest",
        workflowName: "deploy",
        createdAt: "2026-06-10T00:00:00.000Z",
      }),
    ];
    const policy: RetentionPolicy = { maxAgeDays: 7, keepLatestPerWorkflow: 1 };

    const plan = buildDeletionPlan(artifacts, policy, { now: NOW, dryRun: true });

    expect(plan.toDelete.map((d) => d.artifact.id).sort()).toEqual([
      "ci-old",
      "deploy-old",
    ]);
    expect(plan.toRetain.map((d) => d.artifact.id).sort()).toEqual([
      "ci-newest",
      "deploy-newest",
    ]);
  });
});

describe("buildDeletionPlan - combined policies", () => {
  test("applies maxAgeDays, maxTotalSizeBytes, and keepLatestPerWorkflow together", () => {
    const artifacts: Artifact[] = [
      // Protected despite being old: newest of its workflow.
      makeArtifact({
        id: "protected-old",
        workflowName: "ci",
        createdAt: "2026-06-01T00:00:00.000Z",
        sizeInBytes: 2000,
      }),
      // Fresh, but pushes total size over cap, so gets evicted oldest-first.
      makeArtifact({
        id: "size-evicted",
        workflowName: "other",
        createdAt: "2026-06-25T00:00:00.000Z",
        sizeInBytes: 2000,
      }),
      makeArtifact({
        id: "kept",
        workflowName: "other",
        createdAt: "2026-06-30T00:00:00.000Z",
        sizeInBytes: 500,
      }),
    ];
    const policy: RetentionPolicy = {
      maxAgeDays: 100,
      maxTotalSizeBytes: 2500,
      keepLatestPerWorkflow: 1,
    };

    const plan = buildDeletionPlan(artifacts, policy, { now: NOW, dryRun: true });

    expect(plan.toDelete.map((d) => d.artifact.id)).toEqual(["size-evicted"]);
    expect(plan.toRetain.map((d) => d.artifact.id).sort()).toEqual([
      "kept",
      "protected-old",
    ]);
  });
});

describe("summarizePlan", () => {
  test("reports counts and bytes reclaimed", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "a", createdAt: "2026-06-01T00:00:00.000Z", sizeInBytes: 100 }),
      makeArtifact({ id: "b", createdAt: "2026-06-30T00:00:00.000Z", sizeInBytes: 200 }),
    ];
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7 }, { now: NOW, dryRun: true });

    const summary = summarizePlan(plan);

    expect(summary).toEqual({
      deletedCount: 1,
      retainedCount: 1,
      totalBytesReclaimed: 100,
      dryRun: true,
    });
  });
});

describe("buildDeletionPlan - input validation", () => {
  test("throws a meaningful error for a negative maxAgeDays", () => {
    expect(() =>
      buildDeletionPlan([makeArtifact({})], { maxAgeDays: -1 }, { now: NOW }),
    ).toThrow(/maxAgeDays must be non-negative/);
  });

  test("throws a meaningful error for a negative maxTotalSizeBytes", () => {
    expect(() =>
      buildDeletionPlan(
        [makeArtifact({})],
        { maxTotalSizeBytes: -5 },
        { now: NOW },
      ),
    ).toThrow(/maxTotalSizeBytes must be non-negative/);
  });

  test("throws a meaningful error for an artifact with an invalid createdAt", () => {
    expect(() =>
      buildDeletionPlan(
        [makeArtifact({ createdAt: "not-a-date" })],
        { maxAgeDays: 7 },
        { now: NOW },
      ),
    ).toThrow(/invalid createdAt/);
  });
});
