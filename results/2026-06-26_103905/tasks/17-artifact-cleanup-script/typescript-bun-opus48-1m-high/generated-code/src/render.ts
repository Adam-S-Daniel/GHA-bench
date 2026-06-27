/**
 * Human-readable rendering of a DeletionPlan.
 *
 * Kept separate from both the planner (pure logic) and the CLI (I/O) so the
 * exact output text can be asserted in unit tests and parsed by the CI harness.
 */
import type { Artifact, DeletionPlan } from "./cleanup.ts";

export interface RenderOptions {
  /** When true, the report makes clear nothing was actually deleted. */
  dryRun: boolean;
}

/** Format one artifact as a single, stable, parseable line. */
function describe(artifact: Artifact, verb: "DELETE" | "RETAIN"): string {
  return `  ${verb} ${artifact.name} (${artifact.sizeBytes} bytes, run ${artifact.workflowRunId}) created ${artifact.createdAt}`;
}

/** Render a full plan to a multi-line string suitable for stdout. */
export function renderPlan(plan: DeletionPlan, options: RenderOptions): string {
  const { summary } = plan;
  const lines: string[] = [];

  lines.push("=== Artifact Cleanup Plan ===");
  lines.push(`Mode: ${options.dryRun ? "DRY-RUN" : "LIVE"}`);
  lines.push(`Total artifacts: ${summary.totalArtifacts}`);
  lines.push(`Retained: ${summary.retainedCount}`);
  lines.push(`Deleted: ${summary.deletedCount}`);
  lines.push(`Total size: ${summary.totalSizeBytes} bytes`);
  lines.push(`Space reclaimed: ${summary.spaceReclaimedBytes} bytes`);
  lines.push(`Retained size: ${summary.retainedSizeBytes} bytes`);

  lines.push("");
  lines.push("Artifacts to delete:");
  if (plan.toDelete.length === 0) {
    lines.push("  (none)");
  } else {
    for (const a of plan.toDelete) lines.push(describe(a, "DELETE"));
  }

  lines.push("");
  lines.push("Artifacts to retain:");
  if (plan.toRetain.length === 0) {
    lines.push("  (none)");
  } else {
    for (const a of plan.toRetain) lines.push(describe(a, "RETAIN"));
  }

  lines.push("");
  if (options.dryRun) {
    lines.push("DRY-RUN: no artifacts were deleted (plan only).");
  } else {
    lines.push(
      `LIVE: deleted ${summary.deletedCount} artifact(s), reclaiming ${summary.spaceReclaimedBytes} bytes.`,
    );
  }

  return lines.join("\n");
}
