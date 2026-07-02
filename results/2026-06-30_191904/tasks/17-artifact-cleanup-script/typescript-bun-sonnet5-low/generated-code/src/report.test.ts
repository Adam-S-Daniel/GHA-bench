import { describe, expect, test } from "bun:test";
import { buildCleanupPlan } from "./retention";
import { formatReport } from "./report";

describe("formatReport", () => {
  test("renders a human-readable summary with delete/retain lists and dry-run flag", () => {
    const artifacts = [
      {
        id: "a",
        name: "build",
        sizeBytes: 1000,
        createdAt: "2026-01-01T00:00:00.000Z",
        workflowRunId: "r1",
        workflowName: "ci",
      },
      {
        id: "b",
        name: "build",
        sizeBytes: 2000,
        createdAt: "2026-06-30T00:00:00.000Z",
        workflowRunId: "r2",
        workflowName: "ci",
      },
    ];

    const plan = buildCleanupPlan(
      artifacts,
      { maxAgeDays: 30 },
      { now: new Date("2026-07-01T00:00:00.000Z"), dryRun: true }
    );
    const report = formatReport(plan);

    expect(report).toContain("DRY RUN");
    expect(report).toContain("Total artifacts: 2");
    expect(report).toContain("Retained: 1");
    expect(report).toContain("Deleted: 1");
    expect(report).toContain("Space reclaimed: 1000 bytes");
    expect(report).toContain("[DELETE] a (build)");
    expect(report).toContain("[KEEP]   b (build)");
  });
});
