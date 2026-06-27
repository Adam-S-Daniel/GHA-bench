import { describe, it, expect } from "bun:test";
import {
  planCleanup,
  renderReport,
  type Artifact,
} from "./cleanup.ts";

// Helper to build artifacts with sensible defaults, keeping the tests terse.
function artifact(over: Partial<Artifact> & { name: string }): Artifact {
  return {
    sizeBytes: 100,
    createdAt: "2026-06-01T00:00:00Z",
    workflowName: "ci",
    workflowRunId: 1,
    ...over,
  };
}

// Red/green TDD: first failing test — the planner must exist and, given no
// policies, retain every artifact and delete nothing.
describe("planCleanup — no policies", () => {
  it("retains all artifacts when no retention policy is configured", () => {
    const artifacts: Artifact[] = [
      {
        name: "build-output",
        sizeBytes: 1000,
        createdAt: "2026-06-01T00:00:00Z",
        workflowName: "ci",
        workflowRunId: 1,
      },
    ];

    const plan = planCleanup(artifacts, {}, { now: "2026-06-26T00:00:00Z" });

    expect(plan.toDelete).toHaveLength(0);
    expect(plan.toRetain).toHaveLength(1);
    expect(plan.summary.bytesReclaimed).toBe(0);
  });
});

describe("planCleanup — max age policy", () => {
  it("deletes artifacts older than maxAgeDays and keeps newer ones", () => {
    const artifacts: Artifact[] = [
      // 40 days old -> should be deleted (maxAgeDays = 30)
      {
        name: "old",
        sizeBytes: 500,
        createdAt: "2026-05-17T00:00:00Z",
        workflowName: "ci",
        workflowRunId: 1,
      },
      // 5 days old -> retained
      {
        name: "fresh",
        sizeBytes: 700,
        createdAt: "2026-06-21T00:00:00Z",
        workflowName: "ci",
        workflowRunId: 2,
      },
    ];

    const plan = planCleanup(
      artifacts,
      { maxAgeDays: 30 },
      { now: "2026-06-26T00:00:00Z" },
    );

    expect(plan.toDelete.map((d) => d.artifact.name)).toEqual(["old"]);
    expect(plan.toDelete[0]!.reason).toBe("max-age");
    expect(plan.toRetain.map((a) => a.name)).toEqual(["fresh"]);
    expect(plan.summary.bytesReclaimed).toBe(500);
    expect(plan.summary.bytesRetained).toBe(700);
  });
});

describe("planCleanup — keep-latest-N per workflow", () => {
  it("keeps the N most recent artifacts per workflow and deletes the rest", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "ci-1", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 1000, workflowRunId: 1 }),
      artifact({ name: "ci-2", createdAt: "2026-06-02T00:00:00Z", sizeBytes: 2000, workflowRunId: 2 }),
      artifact({ name: "ci-3", createdAt: "2026-06-03T00:00:00Z", sizeBytes: 3000, workflowRunId: 3 }),
      // Different workflow with a single artifact -> always retained.
      artifact({ name: "build-1", workflowName: "build", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 500, workflowRunId: 4 }),
    ];

    const plan = planCleanup(
      artifacts,
      { keepLatestNPerWorkflow: 2 },
      { now: "2026-06-26T00:00:00Z" },
    );

    // ci-1 is the oldest of the three "ci" artifacts -> deleted.
    expect(plan.toDelete.map((d) => d.artifact.name)).toEqual(["ci-1"]);
    expect(plan.toDelete[0]!.reason).toBe("keep-latest-n");
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual([
      "build-1",
      "ci-2",
      "ci-3",
    ]);
    expect(plan.summary.bytesReclaimed).toBe(1000);
  });

  it("protects the latest N even when they are older than maxAgeDays", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "old-kept", createdAt: "2026-01-01T00:00:00Z", sizeBytes: 100, workflowRunId: 1 }),
      artifact({ name: "older-deleted", createdAt: "2025-12-01T00:00:00Z", sizeBytes: 200, workflowRunId: 2 }),
    ];

    const plan = planCleanup(
      artifacts,
      { keepLatestNPerWorkflow: 1, maxAgeDays: 30 },
      { now: "2026-06-26T00:00:00Z" },
    );

    // The newest ("old-kept") is protected by keep-latest-N despite being old.
    expect(plan.toRetain.map((a) => a.name)).toEqual(["old-kept"]);
    expect(plan.toDelete.map((d) => d.artifact.name)).toEqual(["older-deleted"]);
  });
});

describe("planCleanup — max total size policy", () => {
  it("deletes oldest artifacts until retained total is within budget", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "a", createdAt: "2026-06-01T00:00:00Z", sizeBytes: 1000, workflowRunId: 1 }),
      artifact({ name: "b", createdAt: "2026-06-02T00:00:00Z", sizeBytes: 2000, workflowRunId: 2 }),
      artifact({ name: "c", createdAt: "2026-06-03T00:00:00Z", sizeBytes: 3000, workflowRunId: 3 }),
    ];

    const plan = planCleanup(
      artifacts,
      { maxTotalSizeBytes: 3500 },
      { now: "2026-06-26T00:00:00Z" },
    );

    // Total is 6000; deleting a (1000) and b (2000) leaves 3000 <= 3500.
    expect(plan.toDelete.map((d) => d.artifact.name).sort()).toEqual(["a", "b"]);
    expect(plan.toDelete.every((d) => d.reason === "max-total-size")).toBe(true);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["c"]);
    expect(plan.summary.bytesRetained).toBe(3000);
    expect(plan.summary.bytesReclaimed).toBe(3000);
  });
});

describe("planCleanup — dry-run flag", () => {
  it("passes the dry-run flag through to the plan", () => {
    const plan = planCleanup(
      [artifact({ name: "x" })],
      {},
      { now: "2026-06-26T00:00:00Z", dryRun: true },
    );
    expect(plan.dryRun).toBe(true);
  });
});

describe("planCleanup — error handling", () => {
  it("throws a meaningful error for an invalid createdAt date", () => {
    const artifacts: Artifact[] = [
      artifact({ name: "bad", createdAt: "not-a-date" }),
    ];
    expect(() =>
      planCleanup(artifacts, { maxAgeDays: 1 }, { now: "2026-06-26T00:00:00Z" }),
    ).toThrow(/Invalid date/);
  });

  it("throws when sizeBytes is negative", () => {
    const artifacts: Artifact[] = [artifact({ name: "neg", sizeBytes: -5 })];
    expect(() => planCleanup(artifacts, {}, {})).toThrow(/invalid sizeBytes/);
  });
});

describe("renderReport", () => {
  it("emits stable machine-parseable KEY=value lines", () => {
    const plan = planCleanup(
      [
        artifact({ name: "keep", sizeBytes: 700, createdAt: "2026-06-25T00:00:00Z", workflowRunId: 2 }),
        artifact({ name: "old", sizeBytes: 500, createdAt: "2026-01-01T00:00:00Z", workflowRunId: 1 }),
      ],
      { maxAgeDays: 30 },
      { now: "2026-06-26T00:00:00Z", dryRun: true },
    );
    const report = renderReport(plan);

    expect(report).toContain("MODE=DRY-RUN");
    expect(report).toContain("DELETED_COUNT=1");
    expect(report).toContain("RETAINED_COUNT=1");
    expect(report).toContain("BYTES_RECLAIMED=500");
    expect(report).toContain("BYTES_RETAINED=700");
    expect(report).toContain("DELETE old reason=max-age size=500");
  });
});

describe("planCleanup — keep latest N per workflow", () => {
  it("protects the N newest artifacts per workflow from age-based deletion", () => {
    const artifacts: Artifact[] = [
      // All old (well past 30 days), two different workflows.
      { name: "ci-1", sizeBytes: 100, createdAt: "2026-01-01T00:00:00Z", workflowName: "ci", workflowRunId: 1 },
      { name: "ci-2", sizeBytes: 100, createdAt: "2026-02-01T00:00:00Z", workflowName: "ci", workflowRunId: 2 },
      { name: "ci-3", sizeBytes: 100, createdAt: "2026-03-01T00:00:00Z", workflowName: "ci", workflowRunId: 3 },
      { name: "rel-1", sizeBytes: 100, createdAt: "2026-01-15T00:00:00Z", workflowName: "release", workflowRunId: 4 },
    ];

    const plan = planCleanup(
      artifacts,
      { maxAgeDays: 30, keepLatestNPerWorkflow: 1 },
      { now: "2026-06-26T00:00:00Z" },
    );

    // Newest of each workflow is protected: ci-3 (March) and rel-1 (only one).
    expect(plan.toRetain.map((a) => a.name).sort()).toEqual(["ci-3", "rel-1"]);
    expect(plan.toDelete.map((d) => d.artifact.name).sort()).toEqual(["ci-1", "ci-2"]);
  });
});

describe("planCleanup — max total size", () => {
  it("deletes oldest artifacts until total retained size is within budget", () => {
    const artifacts: Artifact[] = [
      { name: "a", sizeBytes: 300, createdAt: "2026-06-01T00:00:00Z", workflowName: "ci", workflowRunId: 1 },
      { name: "b", sizeBytes: 300, createdAt: "2026-06-10T00:00:00Z", workflowName: "ci", workflowRunId: 2 },
      { name: "c", sizeBytes: 300, createdAt: "2026-06-20T00:00:00Z", workflowName: "ci", workflowRunId: 3 },
    ];

    // Budget 700 bytes: total 900 -> must drop the oldest (a) to reach 600.
    const plan = planCleanup(
      artifacts,
      { maxTotalSizeBytes: 700 },
      { now: "2026-06-26T00:00:00Z" },
    );

    expect(plan.toDelete.map((d) => d.artifact.name)).toEqual(["a"]);
    expect(plan.toDelete[0]!.reason).toBe("max-total-size");
    expect(plan.summary.bytesRetained).toBe(600);
    expect(plan.summary.bytesReclaimed).toBe(300);
  });

  it("never deletes keep-latest-N protected artifacts even to meet the size cap", () => {
    const artifacts: Artifact[] = [
      { name: "a", sizeBytes: 300, createdAt: "2026-06-01T00:00:00Z", workflowName: "ci", workflowRunId: 1 },
      { name: "b", sizeBytes: 300, createdAt: "2026-06-20T00:00:00Z", workflowName: "ci", workflowRunId: 2 },
    ];

    // Cap of 100 is unsatisfiable because both are protected (keep 2).
    const plan = planCleanup(
      artifacts,
      { maxTotalSizeBytes: 100, keepLatestNPerWorkflow: 2 },
      { now: "2026-06-26T00:00:00Z" },
    );

    expect(plan.toDelete).toHaveLength(0);
    expect(plan.summary.bytesRetained).toBe(600);
  });
});

describe("planCleanup — combined policies & dry-run", () => {
  it("applies age then size, and reflects dry-run flag in the plan", () => {
    const artifacts: Artifact[] = [
      { name: "ancient", sizeBytes: 500, createdAt: "2026-01-01T00:00:00Z", workflowName: "ci", workflowRunId: 1 },
      { name: "old", sizeBytes: 500, createdAt: "2026-05-01T00:00:00Z", workflowName: "ci", workflowRunId: 2 },
      { name: "recent", sizeBytes: 500, createdAt: "2026-06-24T00:00:00Z", workflowName: "ci", workflowRunId: 3 },
    ];

    const plan = planCleanup(
      artifacts,
      { maxAgeDays: 30, maxTotalSizeBytes: 400, keepLatestNPerWorkflow: 1 },
      { now: "2026-06-26T00:00:00Z", dryRun: true },
    );

    // ancient & old deleted by age; recent protected by keep-latest-1.
    // Size cap of 400 cannot evict recent (protected), so it stays.
    expect(plan.dryRun).toBe(true);
    expect(plan.toDelete.map((d) => d.artifact.name).sort()).toEqual(["ancient", "old"]);
    expect(plan.toRetain.map((a) => a.name)).toEqual(["recent"]);
    expect(plan.summary.bytesReclaimed).toBe(1000);
  });
});

describe("planCleanup — error handling", () => {
  it("throws a meaningful error for an invalid creation date", () => {
    const artifacts: Artifact[] = [
      { name: "bad", sizeBytes: 1, createdAt: "not-a-date", workflowName: "ci", workflowRunId: 1 },
    ];
    expect(() =>
      planCleanup(artifacts, { maxAgeDays: 1 }, { now: "2026-06-26T00:00:00Z" }),
    ).toThrow(/Invalid date/);
  });

  it("throws for a negative size", () => {
    const artifacts = [
      { name: "x", sizeBytes: -5, createdAt: "2026-06-01T00:00:00Z", workflowName: "ci", workflowRunId: 1 },
    ] as Artifact[];
    expect(() => planCleanup(artifacts, {})).toThrow(/invalid sizeBytes/);
  });
});
