import { describe, test, expect } from "bun:test";
import { planCleanup, validateArtifacts, validatePolicy } from "../src/cleanup.ts";
import type { Artifact, RetentionPolicy } from "../src/types.ts";

// A fixed reference "now" makes age-based policies deterministic in tests.
const NOW = new Date("2026-01-01T00:00:00Z");

/** Helper to build an artifact with sensible defaults. */
function art(overrides: Partial<Artifact> & Pick<Artifact, "id">): Artifact {
  return {
    name: overrides.name ?? overrides.id,
    sizeBytes: 1000,
    createdAt: "2025-12-31T00:00:00Z",
    workflowRunId: "wf-1",
    ...overrides,
  };
}

/** Collect the ids that a plan marks for deletion, in input order. */
function deletedIds(artifacts: Artifact[], policy: RetentionPolicy): string[] {
  return planCleanup(artifacts, policy, { now: NOW })
    .decisions.filter((d) => d.delete)
    .map((d) => d.artifact.id);
}

describe("planCleanup — empty input", () => {
  test("returns an empty plan with a zeroed summary when there are no artifacts", () => {
    const policy: RetentionPolicy = {};
    const plan = planCleanup([], policy, { now: NOW });

    expect(plan.decisions).toEqual([]);
    expect(plan.summary).toEqual({
      totalArtifacts: 0,
      retainedCount: 0,
      deletedCount: 0,
      totalSizeBytes: 0,
      retainedSizeBytes: 0,
      spaceReclaimedBytes: 0,
    });
    // Default mode is a real (non-dry-run) plan unless requested otherwise.
    expect(plan.dryRun).toBe(false);
  });
});

describe("planCleanup — max-age policy", () => {
  test("deletes artifacts strictly older than maxAgeDays and keeps the boundary", () => {
    const artifacts: Artifact[] = [
      art({ id: "fresh", createdAt: "2025-12-31T00:00:00Z" }), // 1 day old
      art({ id: "boundary", createdAt: "2025-12-02T00:00:00Z" }), // exactly 30 days
      art({ id: "old", createdAt: "2025-11-01T00:00:00Z" }), // 61 days
    ];
    // 30 days old is NOT > 30, so the boundary artifact is retained.
    expect(deletedIds(artifacts, { maxAgeDays: 30 })).toEqual(["old"]);
  });

  test("attaches the 'max-age' reason code", () => {
    const artifacts: Artifact[] = [art({ id: "old", createdAt: "2024-01-01T00:00:00Z" })];
    const plan = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW });
    expect(plan.decisions[0]!.reasons).toEqual(["max-age"]);
  });
});

describe("planCleanup — keep-latest-N per workflow", () => {
  test("keeps the N newest per workflow run id and deletes the rest", () => {
    const artifacts: Artifact[] = [
      art({ id: "a-new", workflowRunId: "wf-A", createdAt: "2025-12-05T00:00:00Z" }),
      art({ id: "a-mid", workflowRunId: "wf-A", createdAt: "2025-12-04T00:00:00Z" }),
      art({ id: "a-old", workflowRunId: "wf-A", createdAt: "2025-12-03T00:00:00Z" }),
      art({ id: "b-only", workflowRunId: "wf-B", createdAt: "2025-12-01T00:00:00Z" }),
    ];
    // wf-A keeps the 2 newest (a-new, a-mid); a-old deleted. wf-B keeps its only one.
    expect(deletedIds(artifacts, { keepLatestNPerWorkflow: 2 })).toEqual(["a-old"]);
  });

  test("keepLatestNPerWorkflow of 0 deletes everything", () => {
    const artifacts: Artifact[] = [art({ id: "x" }), art({ id: "y" })];
    expect(deletedIds(artifacts, { keepLatestNPerWorkflow: 0 })).toEqual(["x", "y"]);
  });

  test("groups are independent — a busy workflow does not affect a quiet one", () => {
    const artifacts: Artifact[] = [
      art({ id: "p1", workflowRunId: "wf-P", createdAt: "2025-12-10T00:00:00Z" }),
      art({ id: "p2", workflowRunId: "wf-P", createdAt: "2025-12-09T00:00:00Z" }),
      art({ id: "q1", workflowRunId: "wf-Q", createdAt: "2025-12-08T00:00:00Z" }),
    ];
    expect(deletedIds(artifacts, { keepLatestNPerWorkflow: 1 })).toEqual(["p2"]);
  });
});

describe("planCleanup — max total size", () => {
  test("deletes oldest survivors until retained total fits under the cap", () => {
    const artifacts: Artifact[] = [
      art({ id: "newest", sizeBytes: 4000, createdAt: "2025-12-31T00:00:00Z" }),
      art({ id: "middle", sizeBytes: 4000, createdAt: "2025-12-30T00:00:00Z" }),
      art({ id: "oldest", sizeBytes: 4000, createdAt: "2025-12-29T00:00:00Z" }),
    ];
    // total 12000, cap 9000 -> delete the single oldest (4000) -> 8000 <= 9000.
    expect(deletedIds(artifacts, { maxTotalSizeBytes: 9000 })).toEqual(["oldest"]);
  });

  test("does nothing when the retained total already fits", () => {
    const artifacts: Artifact[] = [art({ id: "a", sizeBytes: 100 }), art({ id: "b", sizeBytes: 100 })];
    expect(deletedIds(artifacts, { maxTotalSizeBytes: 1000 })).toEqual([]);
  });

  test("a cap of 0 deletes everything", () => {
    const artifacts: Artifact[] = [art({ id: "a", sizeBytes: 1 }), art({ id: "b", sizeBytes: 1 })];
    expect(deletedIds(artifacts, { maxTotalSizeBytes: 0 })).toEqual(["a", "b"]);
  });
});

describe("planCleanup — combined policies", () => {
  test("rules are additive and an artifact accumulates every matching reason", () => {
    const artifacts: Artifact[] = [
      art({ id: "a1", workflowRunId: "wf-1", sizeBytes: 1000, createdAt: "2025-12-31T00:00:00Z" }),
      art({ id: "a2", workflowRunId: "wf-1", sizeBytes: 2000, createdAt: "2025-12-30T00:00:00Z" }),
      art({ id: "a3", workflowRunId: "wf-1", sizeBytes: 3000, createdAt: "2025-11-01T00:00:00Z" }),
      art({ id: "a4", workflowRunId: "wf-2", sizeBytes: 5000, createdAt: "2025-01-01T00:00:00Z" }),
    ];
    const policy: RetentionPolicy = {
      maxAgeDays: 30,
      keepLatestNPerWorkflow: 2,
      maxTotalSizeBytes: 10000,
    };
    const plan = planCleanup(artifacts, policy, { now: NOW });
    const byId = Object.fromEntries(plan.decisions.map((d) => [d.artifact.id, d]));

    expect(byId["a1"]!.delete).toBe(false);
    expect(byId["a2"]!.delete).toBe(false);
    // a3 is old (>30d) AND the 3rd-newest in wf-1 -> two reasons.
    expect(byId["a3"]!.delete).toBe(true);
    expect(byId["a3"]!.reasons).toEqual(["max-age", "keep-latest-n"]);
    expect(byId["a4"]!.delete).toBe(true);
    expect(byId["a4"]!.reasons).toEqual(["max-age"]);

    expect(plan.summary).toEqual({
      totalArtifacts: 4,
      retainedCount: 2,
      deletedCount: 2,
      totalSizeBytes: 11000,
      retainedSizeBytes: 3000,
      spaceReclaimedBytes: 8000,
    });
  });
});

describe("planCleanup — dry-run flag", () => {
  test("dryRun is echoed onto the plan without changing decisions", () => {
    const artifacts: Artifact[] = [art({ id: "old", createdAt: "2024-01-01T00:00:00Z" })];
    const wet = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW, dryRun: false });
    const dry = planCleanup(artifacts, { maxAgeDays: 30 }, { now: NOW, dryRun: true });
    expect(wet.dryRun).toBe(false);
    expect(dry.dryRun).toBe(true);
    expect(dry.summary).toEqual(wet.summary);
  });
});

describe("validation — meaningful errors", () => {
  test("rejects a negative size", () => {
    expect(() => validateArtifacts([art({ id: "bad", sizeBytes: -5 })])).toThrow(/invalid "sizeBytes"/);
  });

  test("rejects an unparseable createdAt", () => {
    expect(() => validateArtifacts([art({ id: "bad", createdAt: "not-a-date" })])).toThrow(
      /unparseable "createdAt"/,
    );
  });

  test("rejects an empty id", () => {
    expect(() => validateArtifacts([art({ id: "" })])).toThrow(/missing or empty "id"/);
  });

  test("rejects duplicate ids", () => {
    expect(() => validateArtifacts([art({ id: "dup" }), art({ id: "dup" })])).toThrow(
      /duplicate artifact id/,
    );
  });

  test("rejects a negative maxAgeDays", () => {
    expect(() => validatePolicy({ maxAgeDays: -1 })).toThrow(/maxAgeDays/);
  });

  test("rejects a non-integer keepLatestNPerWorkflow", () => {
    expect(() => validatePolicy({ keepLatestNPerWorkflow: 1.5 })).toThrow(/keepLatestNPerWorkflow/);
  });

  test("planCleanup surfaces validation errors", () => {
    expect(() => planCleanup([art({ id: "bad", sizeBytes: -1 })], {}, { now: NOW })).toThrow(
      /sizeBytes/,
    );
  });
});

describe("planCleanup — no policy is a no-op", () => {
  test("with an empty policy nothing is deleted", () => {
    const artifacts: Artifact[] = [art({ id: "a" }), art({ id: "b" })];
    const plan = planCleanup(artifacts, {}, { now: NOW });
    expect(plan.summary.deletedCount).toBe(0);
    expect(plan.summary.retainedCount).toBe(2);
    expect(plan.summary.spaceReclaimedBytes).toBe(0);
  });
});
