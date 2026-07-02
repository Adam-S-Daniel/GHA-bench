// Renders a CleanupPlan as a human-readable text report suitable for
// console/CI log output.
import type { CleanupPlan } from "./types";

export interface ReportOptions {
  dryRun: boolean;
}

export function formatPlanReport(plan: CleanupPlan, options: ReportOptions): string {
  const { summary } = plan;
  const lines: string[] = [];

  lines.push(
    options.dryRun ? "Mode: DRY RUN (no artifacts deleted)" : "Mode: LIVE (artifacts were deleted)",
  );
  lines.push(`Total artifacts: ${summary.totalArtifacts}`);
  lines.push(`Retained: ${summary.retainedCount}`);
  lines.push(`Deleted: ${summary.deletedCount}`);
  lines.push(`Reclaimed: ${summary.reclaimedSizeInBytes} bytes`);
  lines.push(
    `Deleted by reason: max-age=${summary.deletedByReason["max-age"]}, ` +
      `keep-latest-n=${summary.deletedByReason["keep-latest-n"]}, ` +
      `max-total-size=${summary.deletedByReason["max-total-size"]}`,
  );

  if (plan.deletions.length > 0) {
    lines.push("Deletions:");
    for (const { artifact, reason } of plan.deletions) {
      lines.push(`  [${reason}] ${artifact.id} (${artifact.sizeInBytes} bytes)`);
    }
  }

  return lines.join("\n");
}
