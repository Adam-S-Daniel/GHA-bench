import { describe, expect, test } from "bun:test";
import { type Artifact, planCleanup } from "./cleanup.ts";

// A fixed reference time so age-based tests are deterministic regardless of
// when the suite runs. All test artifacts are dated relative to this.
const NOW = new Date("2026-06-28T00:00:00Z");

/** Build an artifact with sane defaults; override fields per test. */
function makeArtifact(overrides: Partial<Artifact> & { id: string }): Artifact {
  return {
    name: `${overrides.id}-artifact`,
    sizeBytes: 1000,
    createdAt: NOW.toISOString(),
    workflowRunId: "run-1",
    ...overrides,
  };
}

const ids = (xs: { id: string }[] | { artifact: Artifact }[]): string[] =>
  xs.map((x) => ("id" in x ? x.id : x.artifact.id));

describe("planCleanup — max-age policy", () => {
  test("deletes artifacts older than maxAgeDays and retains newer ones", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "a1", createdAt: "2026-06-27T00:00:00Z", sizeBytes: 1000 }), // 1d old -> retain
      makeArtifact({ id: "a2", createdAt: "2026-05-01T00:00:00Z", sizeBytes: 4000 }), // ~58d old -> delete
    ];

    const plan = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW });

    expect(plan.toRetain.map((a) => a.id)).toEqual(["a1"]);
    expect(plan.toDelete.map((d) => d.artifact.id)).toEqual(["a2"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["max-age"]);
  });

  test("boundary: an artifact exactly at the cutoff is retained, just past it is deleted", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "edge-keep", createdAt: "2026-05-29T00:00:00Z" }), // exactly 30d -> retain
      makeArtifact({ id: "edge-del", createdAt: "2026-05-28T23:59:59Z" }), // just over 30d -> delete
    ];

    const plan = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW });

    expect(plan.toRetain.map((a) => a.id)).toEqual(["edge-keep"]);
    expect(plan.toDelete.map((d) => d.artifact.id)).toEqual(["edge-del"]);
  });

  // Mirrors fixtures/case-max-age.json — the GHA pipeline asserts these numbers.
  test("matches the max-age fixture scenario exactly", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "a1", createdAt: "2026-06-27T00:00:00Z", sizeBytes: 1000 }),
      makeArtifact({ id: "a2", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 2000 }),
      makeArtifact({ id: "a3", createdAt: "2026-05-01T00:00:00Z", sizeBytes: 4000 }),
      makeArtifact({ id: "a4", createdAt: "2026-01-01T00:00:00Z", sizeBytes: 8000 }),
      makeArtifact({ id: "a5", createdAt: "2026-05-28T00:00:00Z", sizeBytes: 500 }),
    ];

    const plan = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW, dryRun: true });

    expect(plan.summary).toEqual({
      totalArtifacts: 5,
      retainedCount: 2,
      deletedCount: 3,
      totalSizeBytes: 15500,
      spaceReclaimedBytes: 12500,
      retainedSizeBytes: 3000,
    });
    expect(ids(plan.toRetain)).toEqual(["a1", "a2"]);
    expect(ids(plan.toDelete)).toEqual(["a3", "a4", "a5"]);
  });
});

describe("planCleanup — keep-latest-N per workflow", () => {
  test("keeps the N newest artifacts within each workflow group", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "c1", workflowName: "CI", createdAt: "2026-06-20T00:00:00Z" }),
      makeArtifact({ id: "c2", workflowName: "CI", createdAt: "2026-06-21T00:00:00Z" }),
      makeArtifact({ id: "c3", workflowName: "CI", createdAt: "2026-06-22T00:00:00Z" }),
      makeArtifact({ id: "r1", workflowName: "Release", createdAt: "2026-06-10T00:00:00Z" }),
    ];

    const plan = planCleanup(artifacts, { keepLatestNPerWorkflow: 2 }, { now: NOW });

    // CI keeps c3,c2 (newest 2) -> c1 deleted; Release has only r1 -> retained.
    expect(new Set(ids(plan.toRetain))).toEqual(new Set(["c2", "c3", "r1"]));
    expect(ids(plan.toDelete)).toEqual(["c1"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["keep-latest-n"]);
  });

  test("groups by workflowRunId when workflowName is absent", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "x1", workflowRunId: "run-A", createdAt: "2026-06-20T00:00:00Z" }),
      makeArtifact({ id: "x2", workflowRunId: "run-A", createdAt: "2026-06-21T00:00:00Z" }),
      makeArtifact({ id: "y1", workflowRunId: "run-B", createdAt: "2026-06-01T00:00:00Z" }),
    ];

    const plan = planCleanup(artifacts, { keepLatestNPerWorkflow: 1 }, { now: NOW });

    // run-A keeps x2 -> x1 deleted; run-B keeps y1.
    expect(ids(plan.toDelete)).toEqual(["x1"]);
    expect(new Set(ids(plan.toRetain))).toEqual(new Set(["x2", "y1"]));
  });

  // Mirrors fixtures/case-keep-latest.json.
  test("matches the keep-latest fixture scenario exactly", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "c1", workflowName: "CI", createdAt: "2026-06-20T00:00:00Z", sizeBytes: 100 }),
      makeArtifact({ id: "c2", workflowName: "CI", createdAt: "2026-06-21T00:00:00Z", sizeBytes: 200 }),
      makeArtifact({ id: "c3", workflowName: "CI", createdAt: "2026-06-22T00:00:00Z", sizeBytes: 300 }),
      makeArtifact({ id: "c4", workflowName: "CI", createdAt: "2026-06-23T00:00:00Z", sizeBytes: 400 }),
      makeArtifact({ id: "r1", workflowName: "Release", createdAt: "2026-06-10T00:00:00Z", sizeBytes: 1000 }),
      makeArtifact({ id: "r2", workflowName: "Release", createdAt: "2026-06-15T00:00:00Z", sizeBytes: 2000 }),
      makeArtifact({ id: "r3", workflowName: "Release", createdAt: "2026-06-18T00:00:00Z", sizeBytes: 3000 }),
    ];

    const plan = planCleanup(artifacts, { keepLatestNPerWorkflow: 2 }, { now: NOW, dryRun: false });

    expect(plan.summary).toEqual({
      totalArtifacts: 7,
      retainedCount: 4,
      deletedCount: 3,
      totalSizeBytes: 7000,
      spaceReclaimedBytes: 1300,
      retainedSizeBytes: 5700,
    });
    expect(new Set(ids(plan.toDelete))).toEqual(new Set(["c1", "c2", "r1"]));
    expect(plan.dryRun).toBe(false);
  });
});

describe("planCleanup — max-total-size policy", () => {
  test("evicts oldest artifacts first until the retained set fits the cap", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "old", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 3000 }),
      makeArtifact({ id: "mid", createdAt: "2026-06-10T00:00:00Z", sizeBytes: 3000 }),
      makeArtifact({ id: "new", createdAt: "2026-06-20T00:00:00Z", sizeBytes: 3000 }),
    ];

    // Cap 6000: total 9000 -> must evict 3000 -> drop the oldest ("old").
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 6000 }, { now: NOW });

    expect(ids(plan.toDelete)).toEqual(["old"]);
    expect(plan.toDelete[0]?.reasons).toEqual(["max-total-size"]);
    expect(plan.summary.retainedSizeBytes).toBe(6000);
  });

  test("retains everything when already under the cap", () => {
    const artifacts: Artifact[] = [makeArtifact({ id: "only", sizeBytes: 100 })];
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 1000 }, { now: NOW });
    expect(plan.toDelete).toEqual([]);
    expect(ids(plan.toRetain)).toEqual(["only"]);
  });
});

describe("planCleanup — combined policies", () => {
  // Mirrors fixtures/case-combined.json — exercises all three rules and the
  // interaction where max-total-size evicts the survivors of rules 1 & 2.
  test("matches the combined fixture scenario exactly", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "b1", workflowName: "Build", createdAt: "2026-06-27T00:00:00Z", sizeBytes: 2000 }),
      makeArtifact({ id: "b2", workflowName: "Build", createdAt: "2026-06-26T00:00:00Z", sizeBytes: 2000 }),
      makeArtifact({ id: "b3", workflowName: "Build", createdAt: "2026-06-25T00:00:00Z", sizeBytes: 2000 }),
      makeArtifact({ id: "b4", workflowName: "Build", createdAt: "2026-06-24T00:00:00Z", sizeBytes: 1000 }),
      makeArtifact({ id: "b5", workflowName: "Build", createdAt: "2026-03-01T00:00:00Z", sizeBytes: 5000 }),
      makeArtifact({ id: "t1", workflowName: "Test", createdAt: "2026-06-20T00:00:00Z", sizeBytes: 1000 }),
      makeArtifact({ id: "t2", workflowName: "Test", createdAt: "2026-06-10T00:00:00Z", sizeBytes: 1000 }),
      makeArtifact({ id: "t3", workflowName: "Test", createdAt: "2026-02-01T00:00:00Z", sizeBytes: 9000 }),
    ];

    const plan = planCleanup(
      artifacts,
      { maxAgeDays: 60, maxTotalSizeBytes: 5000, keepLatestNPerWorkflow: 3 },
      { now: NOW, dryRun: true },
    );

    expect(plan.summary).toEqual({
      totalArtifacts: 8,
      retainedCount: 2,
      deletedCount: 6,
      totalSizeBytes: 23000,
      spaceReclaimedBytes: 19000,
      retainedSizeBytes: 4000,
    });
    expect(new Set(ids(plan.toRetain))).toEqual(new Set(["b1", "b2"]));

    // Reasons are accumulated in policy-application order.
    const reasonsById = Object.fromEntries(plan.toDelete.map((d) => [d.artifact.id, d.reasons]));
    expect(reasonsById["b5"]).toEqual(["max-age", "keep-latest-n"]);
    expect(reasonsById["b4"]).toEqual(["keep-latest-n"]);
    expect(reasonsById["t3"]).toEqual(["max-age"]);
    expect(reasonsById["b3"]).toEqual(["max-total-size"]);
    expect(reasonsById["t1"]).toEqual(["max-total-size"]);
    expect(reasonsById["t2"]).toEqual(["max-total-size"]);
  });
});

describe("planCleanup — dry-run & no-op behavior", () => {
  test("dryRun flag is reflected in the plan but does not change decisions", () => {
    const artifacts: Artifact[] = [makeArtifact({ id: "a", createdAt: "2026-01-01T00:00:00Z" })];
    const dry = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW, dryRun: true });
    const live = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW, dryRun: false });
    expect(dry.dryRun).toBe(true);
    expect(live.dryRun).toBe(false);
    expect(ids(dry.toDelete)).toEqual(ids(live.toDelete));
  });

  test("empty policy retains everything", () => {
    const artifacts: Artifact[] = [
      makeArtifact({ id: "a", createdAt: "2020-01-01T00:00:00Z", sizeBytes: 999 }),
    ];
    const plan = planCleanup(artifacts, {}, { now: NOW });
    expect(plan.toDelete).toEqual([]);
    expect(plan.summary.spaceReclaimedBytes).toBe(0);
    expect(plan.summary.retainedSizeBytes).toBe(999);
  });

  test("empty artifact list yields an empty, well-formed plan", () => {
    const plan = planCleanup([], { maxAgeDays: 1 }, { now: NOW });
    expect(plan.summary).toEqual({
      totalArtifacts: 0,
      retainedCount: 0,
      deletedCount: 0,
      totalSizeBytes: 0,
      spaceReclaimedBytes: 0,
      retainedSizeBytes: 0,
    });
  });
});

describe("planCleanup — error handling", () => {
  test("rejects a negative size", () => {
    expect(() => planCleanup([makeArtifact({ id: "a", sizeBytes: -1 })], {}, { now: NOW })).toThrow(
      /sizeBytes must be a non-negative number/,
    );
  });

  test("rejects an invalid createdAt date", () => {
    expect(() =>
      planCleanup([makeArtifact({ id: "a", createdAt: "not-a-date" })], {}, { now: NOW }),
    ).toThrow(/createdAt is not a valid date/);
  });

  test("rejects duplicate artifact ids", () => {
    expect(() =>
      planCleanup([makeArtifact({ id: "dup" }), makeArtifact({ id: "dup" })], {}, { now: NOW }),
    ).toThrow(/duplicate artifact id/);
  });

  test("rejects a missing id", () => {
    expect(() => planCleanup([makeArtifact({ id: "" })], {}, { now: NOW })).toThrow(
      /id must be a non-empty string/,
    );
  });

  test("rejects a negative / non-integer policy value", () => {
    const a = [makeArtifact({ id: "a" })];
    expect(() => planCleanup(a, { maxAgeDays: -5 }, { now: NOW })).toThrow(/maxAgeDays/);
    expect(() => planCleanup(a, { keepLatestNPerWorkflow: 1.5 }, { now: NOW })).toThrow(
      /keepLatestNPerWorkflow/,
    );
  });
});

describe("planCleanup — determinism", () => {
  test("input order is preserved and ties are broken stably", () => {
    // Two artifacts share a timestamp; keep-latest-1 must pick deterministically.
    const artifacts: Artifact[] = [
      makeArtifact({ id: "z", workflowName: "W", createdAt: "2026-06-20T00:00:00Z" }),
      makeArtifact({ id: "a", workflowName: "W", createdAt: "2026-06-20T00:00:00Z" }),
    ];
    const p1 = planCleanup(artifacts, { keepLatestNPerWorkflow: 1 }, { now: NOW });
    const p2 = planCleanup(artifacts, { keepLatestNPerWorkflow: 1 }, { now: NOW });
    // byNewestFirst breaks ties by id descending -> "z" is newest, "a" deleted.
    expect(ids(p1.toDelete)).toEqual(["a"]);
    expect(ids(p1.toDelete)).toEqual(ids(p2.toDelete));
  });
});
