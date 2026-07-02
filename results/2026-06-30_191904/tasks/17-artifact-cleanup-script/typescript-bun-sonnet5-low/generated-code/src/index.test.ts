import { describe, expect, test } from "bun:test";
import { runCleanup } from "./index";
import { mockArtifacts } from "./fixtures";

describe("runCleanup", () => {
  test("applies the default policy to the mock fixtures and returns a plan + report", () => {
    const { plan, report } = runCleanup({
      artifacts: mockArtifacts,
      policy: { maxAgeDays: 90, keepLatestPerWorkflow: 1 },
      now: new Date("2026-07-01T00:00:00.000Z"),
      dryRun: true,
    });

    // Artifacts "1" (2026-01-15) and "2" (2026-03-10) are > 90 days old and not the
    // latest in their workflow ("3" is the latest "ci" artifact) -> deleted.
    expect(plan.toDelete.map((a) => a.id)).toEqual(["1", "2"]);
    // Everything else is retained (either recent enough, or the latest per workflow).
    expect(plan.toRetain.map((a) => a.id).sort()).toEqual(["3", "4", "5"]);
    expect(report).toContain("DRY RUN");
    expect(report).toContain("Total artifacts: 5");
  });

  test("throws a clear error when given an empty artifact list", () => {
    expect(() =>
      runCleanup({ artifacts: [], policy: {}, now: new Date("2026-07-01T00:00:00.000Z") })
    ).toThrow(/no artifacts/i);
  });
});
