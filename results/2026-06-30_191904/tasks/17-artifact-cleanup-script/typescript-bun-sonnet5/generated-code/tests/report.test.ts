import { describe, expect, test } from "bun:test";
import { formatPlanReport } from "../src/report";
import type { CleanupPlan } from "../src/types";
import { makeArtifact } from "./helpers";

function makePlan(): CleanupPlan {
  return {
    retained: [makeArtifact({ id: "kept", sizeInBytes: 500 })],
    deletions: [
      { artifact: makeArtifact({ id: "old-one", sizeInBytes: 1000 }), reason: "max-age" },
      { artifact: makeArtifact({ id: "extra-one", sizeInBytes: 2000 }), reason: "keep-latest-n" },
    ],
    summary: {
      totalArtifacts: 3,
      retainedCount: 1,
      deletedCount: 2,
      totalSizeInBytes: 3500,
      retainedSizeInBytes: 500,
      reclaimedSizeInBytes: 3000,
      deletedByReason: { "max-age": 1, "keep-latest-n": 1, "max-total-size": 0 },
    },
  };
}

describe("formatPlanReport", () => {
  test("includes exact retained/deleted counts and reclaimed bytes for dry run", () => {
    const report = formatPlanReport(makePlan(), { dryRun: true });

    expect(report).toContain("Mode: DRY RUN (no artifacts deleted)");
    expect(report).toContain("Total artifacts: 3");
    expect(report).toContain("Retained: 1");
    expect(report).toContain("Deleted: 2");
    expect(report).toContain("Reclaimed: 3000 bytes");
    expect(report).toContain("[max-age] old-one (1000 bytes)");
    expect(report).toContain("[keep-latest-n] extra-one (2000 bytes)");
  });

  test("labels wet runs as LIVE", () => {
    const report = formatPlanReport(makePlan(), { dryRun: false });

    expect(report).toContain("Mode: LIVE (artifacts were deleted)");
  });
});
