import { describe, test, expect } from "bun:test";
import type { Artifact } from "../src/types";
import { buildDeletionPlan } from "../src/retention";
import { formatPlanReport } from "../src/format";

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

describe("formatPlanReport", () => {
  test("renders a human-readable report with exact counts and byte totals", () => {
    const artifacts: Artifact[] = [
      makeArtifact({
        id: "old",
        createdAt: "2026-06-01T00:00:00.000Z",
        sizeInBytes: 4096,
      }),
      makeArtifact({ id: "fresh", createdAt: "2026-06-30T00:00:00.000Z" }),
    ];
    const plan = buildDeletionPlan(
      artifacts,
      { maxAgeDays: 7 },
      { now: NOW, dryRun: true },
    );

    const report = formatPlanReport(plan);

    expect(report).toContain("DRY RUN: true");
    expect(report).toContain("Artifacts retained: 1");
    expect(report).toContain("Artifacts deleted: 1");
    expect(report).toContain("Total space reclaimed: 4096 bytes");
    expect(report).toContain("- old");
  });
});
