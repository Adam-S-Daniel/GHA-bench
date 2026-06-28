/**
 * Rendering of a `DeletionPlan` into human-readable text or machine JSON.
 *
 * The text report ends with a single, stable, grep-friendly `SUMMARY ...` line.
 * That line is the contract the CI pipeline (and its act-based tests) assert on,
 * so its format is deliberately rigid: `key=value` pairs in a fixed order.
 */

import type { DeletionPlan, RetentionPolicy } from "./types.ts";

/** Prefix of the single machine-parseable summary line. */
export const SUMMARY_PREFIX = "SUMMARY";

/** Render the policy as a compact, stable `key=value` list for the header. */
function formatPolicy(policy: RetentionPolicy): string {
  const parts: string[] = [];
  if (policy.maxAgeDays !== undefined) parts.push(`maxAgeDays=${policy.maxAgeDays}`);
  if (policy.maxTotalSizeBytes !== undefined) {
    parts.push(`maxTotalSizeBytes=${policy.maxTotalSizeBytes}`);
  }
  if (policy.keepLatestNPerWorkflow !== undefined) {
    parts.push(`keepLatestNPerWorkflow=${policy.keepLatestNPerWorkflow}`);
  }
  return parts.length > 0 ? parts.join(", ") : "(none)";
}

/** Format an age in days as a short whole-day token, e.g. "61d". */
function formatAge(ageDays: number): string {
  return `${Math.floor(ageDays)}d`;
}

/** Build the canonical machine-parseable summary line. */
export function formatSummaryLine(plan: DeletionPlan): string {
  const s = plan.summary;
  return (
    `${SUMMARY_PREFIX} total=${s.totalArtifacts} retained=${s.retainedCount} ` +
    `deleted=${s.deletedCount} reclaimed_bytes=${s.spaceReclaimedBytes} ` +
    `retained_bytes=${s.retainedSizeBytes} total_bytes=${s.totalSizeBytes}`
  );
}

/** Render the full plan as a human-readable report ending in the SUMMARY line. */
export function formatPlanText(plan: DeletionPlan): string {
  const lines: string[] = [];
  lines.push("=== Artifact Cleanup Plan ===");
  lines.push(`Mode: ${plan.dryRun ? "DRY-RUN" : "EXECUTE"}`);
  lines.push(`Policy: ${formatPolicy(plan.policy)}`);
  lines.push(`Total artifacts: ${plan.summary.totalArtifacts}`);
  lines.push(`Retained: ${plan.summary.retainedCount} (${plan.summary.retainedSizeBytes} bytes)`);
  lines.push(`Deleted: ${plan.summary.deletedCount} (${plan.summary.spaceReclaimedBytes} bytes)`);
  lines.push(`Space reclaimed: ${plan.summary.spaceReclaimedBytes} bytes`);

  const toDelete = plan.decisions.filter((d) => d.delete);
  const toKeep = plan.decisions.filter((d) => !d.delete);

  lines.push("");
  lines.push("Artifacts to delete:");
  if (toDelete.length === 0) {
    lines.push("  (none)");
  } else {
    for (const d of toDelete) {
      lines.push(
        `  - [${d.artifact.id}] ${d.artifact.name} — ${d.artifact.sizeBytes} bytes, ` +
          `${formatAge(d.ageDays)} old :: ${d.reasons.join(", ")}`,
      );
    }
  }

  lines.push("");
  lines.push("Artifacts retained:");
  if (toKeep.length === 0) {
    lines.push("  (none)");
  } else {
    for (const d of toKeep) {
      lines.push(
        `  - [${d.artifact.id}] ${d.artifact.name} — ${d.artifact.sizeBytes} bytes, ` +
          `${formatAge(d.ageDays)} old`,
      );
    }
  }

  lines.push("");
  lines.push(formatSummaryLine(plan));
  return lines.join("\n");
}

/** Render the plan as pretty-printed JSON for programmatic consumers. */
export function formatPlanJson(plan: DeletionPlan): string {
  return JSON.stringify(plan, null, 2);
}
