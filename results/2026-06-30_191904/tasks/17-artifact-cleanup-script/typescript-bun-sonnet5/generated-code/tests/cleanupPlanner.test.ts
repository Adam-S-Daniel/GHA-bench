import { describe, expect, test } from "bun:test";
import { buildCleanupPlan } from "../src/cleanupPlanner";
import { makeArtifact } from "./helpers";

describe("buildCleanupPlan", () => {
  test("applies max-age, then keep-latest-N, then max-total-size in order", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = [
      // Older than 30 days -> deleted by max-age, regardless of other rules.
      makeArtifact({
        id: "ancient",
        workflowId: "ci.yml",
        sizeInBytes: 10,
        createdAt: new Date("2026-01-01T00:00:00Z"),
      }),
      // ci.yml: 3 artifacts within age limit; keepLatestN=2 drops the oldest of these.
      makeArtifact({
        id: "ci-old",
        workflowId: "ci.yml",
        sizeInBytes: 100,
        createdAt: new Date("2026-06-10T00:00:00Z"),
      }),
      makeArtifact({
        id: "ci-mid",
        workflowId: "ci.yml",
        sizeInBytes: 100,
        createdAt: new Date("2026-06-20T00:00:00Z"),
      }),
      makeArtifact({
        id: "ci-new",
        workflowId: "ci.yml",
        sizeInBytes: 100,
        createdAt: new Date("2026-06-25T00:00:00Z"),
      }),
      // release.yml: single artifact, survives age + keepLatestN, but the
      // total-size budget only leaves room for one more artifact after
      // ci-mid/ci-new, so being oldest among survivors, it gets cut.
      makeArtifact({
        id: "release-1",
        workflowId: "release.yml",
        sizeInBytes: 100,
        createdAt: new Date("2026-06-15T00:00:00Z"),
      }),
    ];

    const plan = buildCleanupPlan(
      artifacts,
      { maxAgeInDays: 60, keepLatestN: 2, maxTotalSizeInBytes: 200 },
      now,
    );

    const deletedByReason = Object.fromEntries(
      plan.deletions.map((d) => [d.artifact.id, d.reason]),
    );
    expect(deletedByReason).toEqual({
      ancient: "max-age",
      "ci-old": "keep-latest-n",
      "release-1": "max-total-size",
    });
    expect(plan.retained.map((a) => a.id).sort()).toEqual(["ci-mid", "ci-new"]);
  });

  test("summary reports totals, retained/deleted counts, and reclaimed size", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = [
      makeArtifact({ id: "a", sizeInBytes: 1000, createdAt: new Date("2026-01-01T00:00:00Z") }),
      makeArtifact({ id: "b", sizeInBytes: 500, createdAt: new Date("2026-06-30T00:00:00Z") }),
    ];

    const plan = buildCleanupPlan(artifacts, { maxAgeInDays: 30 }, now);

    expect(plan.summary).toEqual({
      totalArtifacts: 2,
      retainedCount: 1,
      deletedCount: 1,
      totalSizeInBytes: 1500,
      retainedSizeInBytes: 500,
      reclaimedSizeInBytes: 1000,
      deletedByReason: { "max-age": 1, "keep-latest-n": 0, "max-total-size": 0 },
    });
  });

  test("retains everything and reclaims nothing when no policy rules are set", () => {
    const now = new Date("2026-07-01T00:00:00Z");
    const artifacts = [makeArtifact({ id: "a" }), makeArtifact({ id: "b", workflowId: "other.yml" })];

    const plan = buildCleanupPlan(artifacts, {}, now);

    expect(plan.retained.map((a) => a.id).sort()).toEqual(["a", "b"]);
    expect(plan.deletions).toEqual([]);
    expect(plan.summary.reclaimedSizeInBytes).toBe(0);
  });

  test("handles an empty artifact list", () => {
    const plan = buildCleanupPlan([], { maxAgeInDays: 1 }, new Date("2026-07-01T00:00:00Z"));

    expect(plan.retained).toEqual([]);
    expect(plan.deletions).toEqual([]);
    expect(plan.summary.totalArtifacts).toBe(0);
    expect(plan.summary.reclaimedSizeInBytes).toBe(0);
  });

  test("rejects an invalid policy before touching the artifacts", () => {
    expect(() =>
      buildCleanupPlan([makeArtifact({ id: "a" })], { maxAgeInDays: -5 }, new Date()),
    ).toThrow("maxAgeInDays must be >= 0, got -5");
  });

  test("rejects malformed artifacts with a descriptive error", () => {
    expect(() =>
      buildCleanupPlan([makeArtifact({ id: "a", sizeInBytes: -10 })], {}, new Date()),
    ).toThrow('artifact "a" has invalid sizeInBytes: -10 (must be >= 0)');
  });
});
