// Renders a DeletionPlan as a human-readable report, suitable for CI logs.
import type { DeletionPlan } from "./types";
import { summarizePlan } from "./retention";

export function formatPlanReport(plan: DeletionPlan): string {
  const summary = summarizePlan(plan);
  const lines: string[] = [];

  lines.push("Artifact Cleanup Plan");
  lines.push("=====================");
  lines.push(`DRY RUN: ${summary.dryRun}`);
  lines.push(`Artifacts retained: ${summary.retainedCount}`);
  lines.push(`Artifacts deleted: ${summary.deletedCount}`);
  lines.push(`Total space reclaimed: ${summary.totalBytesReclaimed} bytes`);
  lines.push("");

  lines.push("To delete:");
  if (plan.toDelete.length === 0) {
    lines.push("  (none)");
  } else {
    for (const decision of plan.toDelete) {
      lines.push(
        `  - ${decision.artifact.id} (${decision.artifact.name}, ${decision.artifact.sizeInBytes} bytes) — ${decision.reason}`,
      );
    }
  }
  lines.push("");

  lines.push("To retain:");
  if (plan.toRetain.length === 0) {
    lines.push("  (none)");
  } else {
    for (const decision of plan.toRetain) {
      lines.push(
        `  - ${decision.artifact.id} (${decision.artifact.name}, ${decision.artifact.sizeInBytes} bytes) — ${decision.reason}`,
      );
    }
  }

  return lines.join("\n");
}
