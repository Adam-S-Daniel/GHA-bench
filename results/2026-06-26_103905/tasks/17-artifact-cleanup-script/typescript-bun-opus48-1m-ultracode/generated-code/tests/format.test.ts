import { describe, test, expect } from "bun:test";
import { planCleanup } from "../src/cleanup.ts";
import { formatPlanText, formatPlanJson, SUMMARY_PREFIX } from "../src/format.ts";
import type { Artifact, RetentionPolicy } from "../src/types.ts";

const NOW = new Date("2026-01-01T00:00:00Z");

const ARTIFACTS: Artifact[] = [
  { id: "a1", name: "build-1", sizeBytes: 1000, createdAt: "2025-12-31T00:00:00Z", workflowRunId: "wf-1" },
  { id: "a2", name: "build-2", sizeBytes: 2000, createdAt: "2025-12-30T00:00:00Z", workflowRunId: "wf-1" },
  { id: "a3", name: "build-3", sizeBytes: 3000, createdAt: "2025-11-01T00:00:00Z", workflowRunId: "wf-1" },
  { id: "a4", name: "old-build", sizeBytes: 5000, createdAt: "2025-01-01T00:00:00Z", workflowRunId: "wf-2" },
];
const POLICY: RetentionPolicy = { maxAgeDays: 30, keepLatestNPerWorkflow: 2, maxTotalSizeBytes: 10000 };

describe("formatPlanText", () => {
  test("emits a single machine-parseable SUMMARY line with exact counts", () => {
    const plan = planCleanup(ARTIFACTS, POLICY, { now: NOW, dryRun: true });
    const text = formatPlanText(plan);
    const summaryLines = text.split("\n").filter((l) => l.startsWith(SUMMARY_PREFIX));
    expect(summaryLines.length).toBe(1);
    expect(summaryLines[0]).toBe(
      "SUMMARY total=4 retained=2 deleted=2 reclaimed_bytes=8000 retained_bytes=3000 total_bytes=11000",
    );
  });

  test("labels dry-run vs execute mode", () => {
    const dry = formatPlanText(planCleanup(ARTIFACTS, POLICY, { now: NOW, dryRun: true }));
    const wet = formatPlanText(planCleanup(ARTIFACTS, POLICY, { now: NOW, dryRun: false }));
    expect(dry).toContain("Mode: DRY-RUN");
    expect(wet).toContain("Mode: EXECUTE");
  });

  test("lists each deleted artifact with its id, name and reasons", () => {
    const text = formatPlanText(planCleanup(ARTIFACTS, POLICY, { now: NOW, dryRun: true }));
    expect(text).toContain("[a3] build-3");
    expect(text).toContain("max-age, keep-latest-n");
    expect(text).toContain("[a4] old-build");
  });
});

describe("formatPlanJson", () => {
  test("round-trips to an object carrying the summary and decisions", () => {
    const plan = planCleanup(ARTIFACTS, POLICY, { now: NOW, dryRun: true });
    const parsed = JSON.parse(formatPlanJson(plan)) as typeof plan;
    expect(parsed.summary.deletedCount).toBe(2);
    expect(parsed.summary.spaceReclaimedBytes).toBe(8000);
    expect(parsed.decisions.length).toBe(4);
    expect(parsed.dryRun).toBe(true);
  });
});
