import { describe, expect, test } from "bun:test";
import { planCleanup, type Artifact } from "../src/cleanup.ts";
import { renderPlan } from "../src/render.ts";

const NOW = new Date("2026-06-30T00:00:00Z");

const artifacts: Artifact[] = [
  { name: "old", sizeBytes: 600, createdAt: "2026-06-01T00:00:00Z", workflowRunId: 1 },
  { name: "mid", sizeBytes: 600, createdAt: "2026-06-10T00:00:00Z", workflowRunId: 1 },
  { name: "new", sizeBytes: 600, createdAt: "2026-06-20T00:00:00Z", workflowRunId: 1 },
];

describe("renderPlan", () => {
  test("renders the summary block with exact counts and byte totals", () => {
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 1300 }, { now: NOW });
    const out = renderPlan(plan, { dryRun: true });

    expect(out).toContain("=== Artifact Cleanup Plan ===");
    expect(out).toContain("Mode: DRY-RUN");
    expect(out).toContain("Total artifacts: 3");
    expect(out).toContain("Retained: 2");
    expect(out).toContain("Deleted: 1");
    expect(out).toContain("Total size: 1800 bytes");
    expect(out).toContain("Space reclaimed: 600 bytes");
    expect(out).toContain("Retained size: 1200 bytes");
  });

  test("lists each artifact to delete and to retain", () => {
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 1300 }, { now: NOW });
    const out = renderPlan(plan, { dryRun: true });

    expect(out).toContain("DELETE old (600 bytes, run 1)");
    expect(out).toContain("RETAIN mid (600 bytes, run 1)");
    expect(out).toContain("RETAIN new (600 bytes, run 1)");
  });

  test("dry-run footer states nothing was deleted", () => {
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 1300 }, { now: NOW });
    const out = renderPlan(plan, { dryRun: true });
    expect(out).toContain("DRY-RUN: no artifacts were deleted (plan only).");
  });

  test("live-run footer states the deletion happened", () => {
    const plan = planCleanup(artifacts, { maxTotalSizeBytes: 1300 }, { now: NOW });
    const out = renderPlan(plan, { dryRun: false });
    expect(out).toContain("Mode: LIVE");
    expect(out).toContain("LIVE: deleted 1 artifact(s), reclaiming 600 bytes.");
  });
});
