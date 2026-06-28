import { describe, expect, test } from "bun:test";
import { planCleanup, type Artifact, type RetentionPolicy } from "../src/cleanup.ts";

// A small helper to build artifacts concisely in tests.
function artifact(partial: Partial<Artifact> & Pick<Artifact, "name">): Artifact {
  return {
    name: partial.name,
    sizeBytes: partial.sizeBytes ?? 100,
    createdAt: partial.createdAt ?? "2026-06-01T00:00:00Z",
    workflowRunId: partial.workflowRunId ?? 1,
  };
}

// Fixed reference point so age calculations are deterministic in tests.
const NOW = new Date("2026-06-30T00:00:00Z");

describe("max-age policy", () => {
  test("deletes artifacts older than maxAgeDays and retains newer ones", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "fresh", createdAt: "2026-06-29T00:00:00Z" }), // 1 day old
      artifact({ name: "stale", createdAt: "2026-05-01T00:00:00Z" }), // ~60 days old
    ];
    const policy: RetentionPolicy = { maxAgeDays: 30 };

    const plan = planCleanup(artifacts, policy, { now: NOW });

    expect(plan.toDelete.map((a) => a.name)).toEqual(["stale"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["fresh"]);
  });
});

describe("keep-latest-N-per-workflow policy", () => {
  test("keeps only the N most recent artifacts within each workflow run group", () => {
    const artifacts: Artifact[] = [
      // workflow 1: three artifacts, keep the 2 newest -> delete "w1-oldest"
      artifact({ name: "w1-newest", workflowRunId: 1, createdAt: "2026-06-20T00:00:00Z" }),
      artifact({ name: "w1-mid", workflowRunId: 1, createdAt: "2026-06-10T00:00:00Z" }),
      artifact({ name: "w1-oldest", workflowRunId: 1, createdAt: "2026-06-01T00:00:00Z" }),
      // workflow 2: one artifact, never deleted by keep-N
      artifact({ name: "w2-only", workflowRunId: 2, createdAt: "2026-06-05T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = { keepLatestNPerWorkflow: 2 };

    const plan = planCleanup(artifacts, policy, { now: NOW });

    expect(plan.toDelete.map((a) => a.name).sort()).toEqual(["w1-oldest"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["w1-mid", "w1-newest", "w2-only"]);
  });
});

describe("max-total-size policy", () => {
  test("deletes oldest artifacts until retained total fits within the budget", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "old", sizeBytes: 600, createdAt: "2026-06-01T00:00:00Z" }),
      artifact({ name: "mid", sizeBytes: 600, createdAt: "2026-06-10T00:00:00Z" }),
      artifact({ name: "new", sizeBytes: 600, createdAt: "2026-06-20T00:00:00Z" }),
    ];
    // Budget of 1300 bytes fits two 600-byte artifacts (1200) but not three.
    const policy: RetentionPolicy = { maxTotalSizeBytes: 1300 };

    const plan = planCleanup(artifacts, policy, { now: NOW });

    // Oldest is evicted first to bring 1800 -> 1200 (<= 1300).
    expect(plan.toDelete.map((a) => a.name)).toEqual(["old"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["mid", "new"]);
  });
});

describe("plan summary", () => {
  test("reports counts and reclaimed/total bytes", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "old", sizeBytes: 600, createdAt: "2026-06-01T00:00:00Z" }),
      artifact({ name: "mid", sizeBytes: 600, createdAt: "2026-06-10T00:00:00Z" }),
      artifact({ name: "new", sizeBytes: 600, createdAt: "2026-06-20T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = { maxTotalSizeBytes: 1300 };

    const plan = planCleanup(artifacts, policy, { now: NOW });

    expect(plan.summary).toEqual({
      totalArtifacts: 3,
      retainedCount: 2,
      deletedCount: 1,
      totalSizeBytes: 1800,
      spaceReclaimedBytes: 600,
      retainedSizeBytes: 1200,
    });
  });
});

describe("combined policies", () => {
  test("an artifact deleted by any single rule is in the deletion set (union)", () => {
    const artifacts: Artifact[] = [
      // Deleted by max-age (very old), even though it is the latest in its workflow.
      artifact({ name: "ancient", workflowRunId: 9, sizeBytes: 100, createdAt: "2026-01-01T00:00:00Z" }),
      // workflow 1 group: keep-latest-2 will drop the oldest of three.
      artifact({ name: "w1-a", workflowRunId: 1, sizeBytes: 100, createdAt: "2026-06-25T00:00:00Z" }),
      artifact({ name: "w1-b", workflowRunId: 1, sizeBytes: 100, createdAt: "2026-06-24T00:00:00Z" }),
      artifact({ name: "w1-c", workflowRunId: 1, sizeBytes: 100, createdAt: "2026-06-23T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = { maxAgeDays: 30, keepLatestNPerWorkflow: 2 };

    const plan = planCleanup(artifacts, policy, { now: NOW });

    // "ancient" deleted by age; "w1-c" deleted by keep-latest-2. Union of both.
    expect(plan.toDelete.map((a) => a.name).sort()).toEqual(["ancient", "w1-c"]);
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["w1-a", "w1-b"]);
    expect(plan.summary.deletedCount).toBe(2);
  });

  test("an empty artifact list yields an empty, zeroed plan", () => {
    const plan = planCleanup([], { maxAgeDays: 30 }, { now: NOW });
    expect(plan.toDelete).toEqual([]);
    expect(plan.toRetain).toEqual([]);
    expect(plan.summary).toEqual({
      totalArtifacts: 0,
      retainedCount: 0,
      deletedCount: 0,
      totalSizeBytes: 0,
      spaceReclaimedBytes: 0,
      retainedSizeBytes: 0,
    });
  });

  test("an empty policy retains everything", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "a", createdAt: "2020-01-01T00:00:00Z" }),
      artifact({ name: "b" }),
    ];
    const plan = planCleanup(artifacts, {}, { now: NOW });
    expect(plan.toDelete).toEqual([]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["a", "b"]);
  });
});
