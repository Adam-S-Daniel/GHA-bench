import { describe, expect, test } from "bun:test";
import { buildDeletionPlan } from "../src/planner";
import type { Artifact } from "../src/types";

/**
 * Test fixture helper: builds an Artifact with sensible defaults so each test
 * only spells out the fields it cares about.
 */
let nextId = 1;
function artifact(overrides: Partial<Artifact>): Artifact {
  return {
    id: overrides.id ?? nextId++,
    name: overrides.name ?? `artifact-${nextId}`,
    sizeBytes: overrides.sizeBytes ?? 10,
    createdAt: overrides.createdAt ?? "2026-06-30T00:00:00Z",
    workflowRunId: overrides.workflowRunId ?? 1,
  };
}

/** Fixed "now" so age computations are deterministic. */
const NOW = new Date("2026-07-01T00:00:00Z");

describe("max-age policy", () => {
  test("deletes artifacts strictly older than maxAgeDays and retains newer ones", () => {
    const artifacts: Artifact[] = [
      artifact({ id: 1, name: "old", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 100 }),
      artifact({ id: 2, name: "fresh", createdAt: "2026-06-30T00:00:00Z", sizeBytes: 50 }),
    ];

    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7 }, { referenceDate: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["old"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["fresh"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["max-age"]);
  });

  test("an artifact exactly maxAgeDays old is retained (only strictly older is deleted)", () => {
    const artifacts = [artifact({ name: "boundary", createdAt: "2026-06-24T00:00:00Z" })];

    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7 }, { referenceDate: NOW });

    expect(plan.toDelete).toEqual([]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["boundary"]);
  });

  test("with no policies configured, everything is retained", () => {
    const artifacts = [artifact({ name: "a" }), artifact({ name: "b" })];

    const plan = buildDeletionPlan(artifacts, {}, { referenceDate: NOW });

    expect(plan.toDelete).toEqual([]);
    expect(plan.toRetain).toHaveLength(2);
  });

  test("empty artifact list yields an empty plan", () => {
    const plan = buildDeletionPlan([], { maxAgeDays: 1 }, { referenceDate: NOW });

    expect(plan.toDelete).toEqual([]);
    expect(plan.toRetain).toEqual([]);
  });
});

describe("keep-latest-N-per-workflow policy", () => {
  test("keeps only the N most recent artifacts within each workflow run", () => {
    const artifacts: Artifact[] = [
      artifact({ id: 1, name: "run1-oldest", workflowRunId: 100, createdAt: "2026-06-01T00:00:00Z" }),
      artifact({ id: 2, name: "run1-mid", workflowRunId: 100, createdAt: "2026-06-10T00:00:00Z" }),
      artifact({ id: 3, name: "run1-newest", workflowRunId: 100, createdAt: "2026-06-20T00:00:00Z" }),
      artifact({ id: 4, name: "run2-only", workflowRunId: 200, createdAt: "2026-05-01T00:00:00Z" }),
    ];

    const plan = buildDeletionPlan(artifacts, { keepLatestPerWorkflow: 2 }, { referenceDate: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["run1-oldest"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["keep-latest-per-workflow"]);
    // run2 only has one artifact, well within N=2 — untouched even though old.
    expect(plan.toRetain.map((a) => a.name)).toEqual(["run1-mid", "run1-newest", "run2-only"]);
  });

  test("identical timestamps are broken by id (higher id counts as newer)", () => {
    const ts = "2026-06-15T00:00:00Z";
    const artifacts: Artifact[] = [
      artifact({ id: 10, name: "older-id", workflowRunId: 5, createdAt: ts }),
      artifact({ id: 11, name: "newer-id", workflowRunId: 5, createdAt: ts }),
    ];

    const plan = buildDeletionPlan(artifacts, { keepLatestPerWorkflow: 1 }, { referenceDate: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["older-id"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["newer-id"]);
  });

  test("keepLatestPerWorkflow: 0 deletes every artifact", () => {
    const artifacts = [artifact({ name: "a", workflowRunId: 1 })];

    const plan = buildDeletionPlan(artifacts, { keepLatestPerWorkflow: 0 }, { referenceDate: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["a"]);
  });

  test("an artifact doomed by both age and rank reports both reasons", () => {
    const artifacts: Artifact[] = [
      artifact({ id: 1, name: "old-and-outranked", workflowRunId: 1, createdAt: "2026-01-01T00:00:00Z" }),
      artifact({ id: 2, name: "kept", workflowRunId: 1, createdAt: "2026-06-30T00:00:00Z" }),
    ];

    const plan = buildDeletionPlan(
      artifacts,
      { maxAgeDays: 30, keepLatestPerWorkflow: 1 },
      { referenceDate: NOW },
    );

    expect(plan.toDelete).toHaveLength(1);
    expect(plan.toDelete[0]?.reasons).toEqual(["max-age", "keep-latest-per-workflow"]);
  });
});

describe("max-total-size policy", () => {
  test("evicts oldest artifacts until the total size fits the cap", () => {
    const artifacts: Artifact[] = [
      artifact({ id: 1, name: "oldest", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 40 }),
      artifact({ id: 2, name: "middle", createdAt: "2026-06-10T00:00:00Z", sizeBytes: 50 }),
      artifact({ id: 3, name: "newest", createdAt: "2026-06-20T00:00:00Z", sizeBytes: 90 }),
    ];

    // 180 total, cap 150: evict "oldest" (140 left <= 150), stop.
    const plan = buildDeletionPlan(artifacts, { maxTotalSizeBytes: 150 }, { referenceDate: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["oldest"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["max-total-size"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["middle", "newest"]);
  });

  test("size cap only counts artifacts that survived the other policies", () => {
    const artifacts: Artifact[] = [
      // Doomed by age (200 bytes) — must NOT count toward the cap afterwards.
      artifact({ id: 1, name: "ancient", createdAt: "2026-01-01T00:00:00Z", sizeBytes: 200 }),
      artifact({ id: 2, name: "keeper-a", createdAt: "2026-06-25T00:00:00Z", sizeBytes: 60 }),
      artifact({ id: 3, name: "keeper-b", createdAt: "2026-06-28T00:00:00Z", sizeBytes: 30 }),
    ];

    // Survivors total 90 <= cap 100, so nothing extra is evicted.
    const plan = buildDeletionPlan(
      artifacts,
      { maxAgeDays: 30, maxTotalSizeBytes: 100 },
      { referenceDate: NOW },
    );

    expect(plan.toDelete.map((a) => a.name)).toEqual(["ancient"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["keeper-a", "keeper-b"]);
  });
});

describe("combined policies and summary", () => {
  // This mirrors act test case 1 exactly — the known-good numbers asserted in
  // CI are derived from this unit test.
  test("all three policies compose; summary numbers are exact", () => {
    const artifacts: Artifact[] = [
      artifact({ id: 1, name: "A1", workflowRunId: 100, createdAt: "2026-05-01T00:00:00Z", sizeBytes: 100 }),
      artifact({ id: 2, name: "A2", workflowRunId: 100, createdAt: "2026-06-20T00:00:00Z", sizeBytes: 50 }),
      artifact({ id: 3, name: "A3", workflowRunId: 100, createdAt: "2026-06-25T00:00:00Z", sizeBytes: 60 }),
      artifact({ id: 4, name: "A4", workflowRunId: 100, createdAt: "2026-06-28T00:00:00Z", sizeBytes: 70 }),
      artifact({ id: 5, name: "A5", workflowRunId: 200, createdAt: "2026-06-10T00:00:00Z", sizeBytes: 200 }),
      artifact({ id: 6, name: "A6", workflowRunId: 200, createdAt: "2026-06-29T00:00:00Z", sizeBytes: 80 }),
    ];

    const plan = buildDeletionPlan(
      artifacts,
      { maxAgeDays: 30, keepLatestPerWorkflow: 2, maxTotalSizeBytes: 250 },
      { referenceDate: NOW, dryRun: true },
    );

    // A1: too old + rank 4 in run 100. A2: rank 3 in run 100.
    // A5: survivors were A3+A4+A5+A6 = 410 > 250, so evict oldest (A5) -> 210.
    expect(plan.toDelete.map((a) => a.name).sort()).toEqual(["A1", "A2", "A5"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["A3", "A4", "A6"]);
    expect(plan.summary).toEqual({
      totalArtifacts: 6,
      retainedCount: 3,
      deletedCount: 3,
      spaceReclaimedBytes: 350,
      retainedSizeBytes: 210,
    });
    expect(plan.dryRun).toBe(true);
    expect(plan.referenceDate).toBe("2026-07-01T00:00:00.000Z");
  });
});
