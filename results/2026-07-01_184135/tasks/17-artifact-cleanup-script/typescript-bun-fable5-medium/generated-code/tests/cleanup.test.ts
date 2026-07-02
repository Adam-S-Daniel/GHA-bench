/**
 * Unit tests for the artifact cleanup logic — written test-first (red/green TDD).
 * A fixed `NOW` keeps every age computation deterministic.
 */
import { describe, expect, test } from "bun:test";
import {
  executePlan,
  formatPlanReport,
  buildDeletionPlan,
  partitionByKeepLatest,
  partitionByMaxTotalSize,
  partitionByMaxAge,
  type Artifact,
} from "../src/cleanup.ts";

const NOW: Date = new Date("2026-07-01T00:00:00Z");

/** Small helper to build artifacts tersely in tests. */
function art(
  name: string,
  sizeBytes: number,
  createdAt: string,
  workflowRunId: number,
): Artifact {
  return { name, sizeBytes, createdAt, workflowRunId };
}

describe("partitionByMaxAge", () => {
  test("splits artifacts strictly older than maxAgeDays into expired", () => {
    const artifacts: Artifact[] = [
      art("old", 100, "2026-05-15T00:00:00Z", 1), // 47 days old -> expired
      art("edge", 100, "2026-06-01T00:00:01Z", 1), // just under 30 days -> fresh
      art("new", 100, "2026-06-29T00:00:00Z", 1), // 2 days old -> fresh
    ];
    const { expired, fresh } = partitionByMaxAge(artifacts, 30, NOW);
    expect(expired.map((a) => a.name)).toEqual(["old"]);
    expect(fresh.map((a) => a.name)).toEqual(["edge", "new"]);
  });

  test("rejects invalid maxAgeDays with a meaningful error", () => {
    expect(() => partitionByMaxAge([], -1, NOW)).toThrow(
      "maxAgeDays must be a non-negative number, got -1",
    );
  });

  test("rejects artifacts with unparseable createdAt (max-age)", () => {
    const bad = [art("bad", 1, "not-a-date", 1)];
    expect(() => partitionByMaxAge(bad, 30, NOW)).toThrow(
      'artifact "bad" has invalid createdAt: "not-a-date"',
    );
  });
});

describe("partitionByKeepLatest", () => {
  test("keeps only the newest N per workflow run ID", () => {
    const artifacts: Artifact[] = [
      art("a3", 1, "2026-06-24T00:00:00Z", 100), // 3rd newest in run 100 -> evicted
      art("a1", 1, "2026-06-29T00:00:00Z", 100),
      art("a2", 1, "2026-06-27T00:00:00Z", 100),
      art("b1", 1, "2026-06-30T00:00:00Z", 200), // only one in run 200 -> kept
    ];
    const { evicted, kept } = partitionByKeepLatest(artifacts, 2);
    expect(evicted.map((a) => a.name)).toEqual(["a3"]);
    expect(kept.map((a) => a.name).sort()).toEqual(["a1", "a2", "b1"]);
  });

  test("rejects a non-positive-integer N with a meaningful error", () => {
    expect(() => partitionByKeepLatest([], 0)).toThrow(
      "keepLatestPerWorkflow must be a positive integer, got 0",
    );
  });
});

describe("partitionByMaxTotalSize", () => {
  test("evicts oldest artifacts until total size fits the cap", () => {
    const artifacts: Artifact[] = [
      art("newest", 100, "2026-06-29T00:00:00Z", 1),
      art("middle", 80, "2026-06-27T00:00:00Z", 1),
      art("oldest", 70, "2026-06-24T00:00:00Z", 2),
    ]; // total 250, cap 200 -> evict "oldest" (70), still 180 <= 200 done
    const { overflow, kept } = partitionByMaxTotalSize(artifacts, 200);
    expect(overflow.map((a) => a.name)).toEqual(["oldest"]);
    expect(kept.map((a) => a.name).sort()).toEqual(["middle", "newest"]);
  });

  test("returns everything kept when already under the cap", () => {
    const artifacts: Artifact[] = [art("only", 50, "2026-06-29T00:00:00Z", 1)];
    const { overflow, kept } = partitionByMaxTotalSize(artifacts, 50);
    expect(overflow).toEqual([]);
    expect(kept.map((a) => a.name)).toEqual(["only"]);
  });

  test("rejects a negative size cap with a meaningful error", () => {
    expect(() => partitionByMaxTotalSize([], -5)).toThrow(
      "maxTotalSizeBytes must be a non-negative number, got -5",
    );
  });
});

describe("buildDeletionPlan", () => {
  // This fixture mirrors fixtures/case1: three policies each claim one artifact.
  const artifacts: Artifact[] = [
    art("a-old", 52428800, "2026-05-15T00:00:00Z", 100), // 47d -> max-age
    art("a-new1", 104857600, "2026-06-29T00:00:00Z", 100),
    art("a-new2", 83886080, "2026-06-27T00:00:00Z", 100), // -> max-total-size
    art("a-new3", 62914560, "2026-06-24T00:00:00Z", 100), // -> keep-latest
    art("b-1", 73400320, "2026-06-30T00:00:00Z", 200),
  ];

  test("applies max-age, keep-latest, then max-total-size with reasons", () => {
    const plan = buildDeletionPlan(
      artifacts,
      {
        maxAgeDays: 30,
        keepLatestPerWorkflow: 2,
        maxTotalSizeBytes: 209715200, // 200 MiB
        dryRun: true,
      },
      NOW,
    );
    const reasons = new Map(
      plan.toDelete.map((d) => [d.artifact.name, d.reason]),
    );
    expect(reasons.get("a-old")).toBe("max-age");
    expect(reasons.get("a-new3")).toBe("keep-latest");
    expect(reasons.get("a-new2")).toBe("max-total-size");
    expect(plan.retained.map((a) => a.name).sort()).toEqual(["a-new1", "b-1"]);
    expect(plan.summary).toEqual({
      deletedCount: 3,
      retainedCount: 2,
      spaceReclaimedBytes: 199229440,
      dryRun: true,
    });
  });

  test("an empty policy retains everything", () => {
    const plan = buildDeletionPlan(artifacts, {}, NOW);
    expect(plan.toDelete).toEqual([]);
    expect(plan.summary).toEqual({
      deletedCount: 0,
      retainedCount: 5,
      spaceReclaimedBytes: 0,
      dryRun: false,
    });
  });

  test("rejects artifacts with negative sizeBytes", () => {
    const bad = [art("neg", -1, "2026-06-29T00:00:00Z", 1)];
    expect(() => buildDeletionPlan(bad, {}, NOW)).toThrow(
      'artifact "neg" has invalid sizeBytes: -1',
    );
  });

  test("rejects duplicate artifact names", () => {
    const dupes = [
      art("dup", 1, "2026-06-29T00:00:00Z", 1),
      art("dup", 2, "2026-06-30T00:00:00Z", 2),
    ];
    expect(() => buildDeletionPlan(dupes, {}, NOW)).toThrow(
      'duplicate artifact name: "dup"',
    );
  });
});

describe("executePlan / formatPlanReport", () => {
  const artifacts: Artifact[] = [
    art("x1", 10485760, "2026-06-20T00:00:00Z", 300), // 11d -> deleted
    art("x2", 20971520, "2026-06-29T00:00:00Z", 300), // 2d -> retained
  ];

  test("dry-run never calls the deleter", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7, dryRun: true }, NOW);
    const deleted: string[] = [];
    const result = await executePlan(plan, async (a) => {
      deleted.push(a.name);
    });
    expect(deleted).toEqual([]);
    expect(result).toEqual([]);
  });

  test("real run calls the deleter once per planned deletion", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7 }, NOW);
    const deleted: string[] = [];
    const result = await executePlan(plan, async (a) => {
      deleted.push(a.name);
    });
    expect(deleted).toEqual(["x1"]);
    expect(result).toEqual(["x1"]);
  });

  test("a failing deleter surfaces a meaningful error", async () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7 }, NOW);
    await expect(
      executePlan(plan, async () => {
        throw new Error("API rate limit");
      }),
    ).rejects.toThrow('failed to delete artifact "x1": API rate limit');
  });

  test("report contains stable DELETE/RETAIN/SUMMARY lines", () => {
    const plan = buildDeletionPlan(artifacts, { maxAgeDays: 7, dryRun: true }, NOW);
    const report = formatPlanReport(plan);
    expect(report).toContain("MODE dry-run");
    expect(report).toContain("DELETE x1 reason=max-age size=10485760");
    expect(report).toContain("RETAIN x2 size=20971520");
    expect(report).toContain(
      "SUMMARY deleted=1 retained=1 reclaimed_bytes=10485760",
    );
  });
});
