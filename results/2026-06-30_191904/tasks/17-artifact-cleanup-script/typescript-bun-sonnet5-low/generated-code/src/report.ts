// Renders a CleanupPlan as a human-readable text report suitable for CI logs.
import type { CleanupPlan } from "./types";

export function formatReport(plan: CleanupPlan): string {
  const { summary, decisions } = plan;
  const lines: string[] = [];

  lines.push("=== Artifact Cleanup Plan ===");
  if (summary.dryRun) {
    lines.push("Mode: DRY RUN (no artifacts will actually be deleted)");
  } else {
    lines.push("Mode: LIVE");
  }
  lines.push(`Total artifacts: ${summary.totalArtifacts}`);
  lines.push(`Retained: ${summary.retainedCount}`);
  lines.push(`Deleted: ${summary.deletedCount}`);
  lines.push(`Space reclaimed: ${summary.spaceReclaimedBytes} bytes`);
  lines.push("");
  lines.push("--- Details ---");

  for (const decision of decisions) {
    const tag = decision.keep ? "[KEEP]  " : "[DELETE]";
    const reason = decision.reason ? ` (${decision.reason})` : "";
    lines.push(`${tag} ${decision.artifact.id} (${decision.artifact.name})${reason}`);
  }

  return lines.join("\n");
}
