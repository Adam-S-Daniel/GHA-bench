// Core retention-policy logic: decide which artifacts to delete vs retain.
import type {
  Artifact,
  RetentionPolicy,
  DeletionPlan,
  ArtifactDecision,
} from "./types";

export interface BuildPlanOptions {
  /** Reference time to evaluate age against. Defaults to `new Date()`. */
  now?: Date;
  /** When true, the plan is informational only (no deletion is actually performed). */
  dryRun?: boolean;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Validates policy values before use, throwing meaningful errors for bad input. */
function validatePolicy(policy: RetentionPolicy): void {
  if (policy.maxAgeDays !== undefined && policy.maxAgeDays < 0) {
    throw new Error(
      `Invalid retention policy: maxAgeDays must be non-negative, got ${policy.maxAgeDays}`,
    );
  }
  if (
    policy.maxTotalSizeBytes !== undefined &&
    policy.maxTotalSizeBytes < 0
  ) {
    throw new Error(
      `Invalid retention policy: maxTotalSizeBytes must be non-negative, got ${policy.maxTotalSizeBytes}`,
    );
  }
  if (
    policy.keepLatestPerWorkflow !== undefined &&
    policy.keepLatestPerWorkflow < 0
  ) {
    throw new Error(
      `Invalid retention policy: keepLatestPerWorkflow must be non-negative, got ${policy.keepLatestPerWorkflow}`,
    );
  }
}

/**
 * Applies retention policies to a list of artifacts and produces a deletion plan.
 *
 * Only the maxAgeDays policy is implemented so far (further policies are
 * added incrementally via TDD).
 */
export function buildDeletionPlan(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: BuildPlanOptions = {},
): DeletionPlan {
  const now = options.now ?? new Date();
  const dryRun = options.dryRun ?? false;

  validatePolicy(policy);
  for (const artifact of artifacts) {
    if (Number.isNaN(new Date(artifact.createdAt).getTime())) {
      throw new Error(
        `Artifact "${artifact.id}" has an invalid createdAt value: "${artifact.createdAt}"`,
      );
    }
  }

  // keepLatestPerWorkflow overrides every other policy: the N most recent
  // artifacts per workflowName are always protected from deletion.
  const protectedIds = new Set<string>();
  if (policy.keepLatestPerWorkflow !== undefined) {
    const byWorkflow = new Map<string, Artifact[]>();
    for (const artifact of artifacts) {
      const bucket = byWorkflow.get(artifact.workflowName) ?? [];
      bucket.push(artifact);
      byWorkflow.set(artifact.workflowName, bucket);
    }
    for (const bucket of byWorkflow.values()) {
      const newestFirst = [...bucket].sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
      );
      for (const artifact of newestFirst.slice(
        0,
        policy.keepLatestPerWorkflow,
      )) {
        protectedIds.add(artifact.id);
      }
    }
  }

  const toDelete: ArtifactDecision[] = [];
  const toRetain: ArtifactDecision[] = [];

  for (const artifact of artifacts) {
    if (protectedIds.has(artifact.id)) {
      toRetain.push({
        artifact,
        reason: `protected by keepLatestPerWorkflow (${policy.keepLatestPerWorkflow})`,
      });
      continue;
    }
    if (policy.maxAgeDays !== undefined) {
      const ageDays =
        (now.getTime() - new Date(artifact.createdAt).getTime()) / MS_PER_DAY;
      if (ageDays > policy.maxAgeDays) {
        toDelete.push({
          artifact,
          reason: `older than maxAgeDays (${policy.maxAgeDays})`,
        });
        continue;
      }
    }
    toRetain.push({ artifact, reason: "within retention policy" });
  }

  if (policy.maxTotalSizeBytes !== undefined) {
    // Oldest-first eviction: sort survivors by creation date ascending and
    // delete from the front until the retained total fits under the cap.
    toRetain.sort(
      (a, b) =>
        new Date(a.artifact.createdAt).getTime() -
        new Date(b.artifact.createdAt).getTime(),
    );

    let total = toRetain.reduce((sum, d) => sum + d.artifact.sizeInBytes, 0);
    let i = 0;
    while (total > policy.maxTotalSizeBytes && i < toRetain.length) {
      const candidate = toRetain[i]!;
      if (protectedIds.has(candidate.artifact.id)) {
        i++;
        continue;
      }
      toRetain.splice(i, 1);
      total -= candidate.artifact.sizeInBytes;
      toDelete.push({
        artifact: candidate.artifact,
        reason: `exceeds maxTotalSizeBytes cap (${policy.maxTotalSizeBytes})`,
      });
    }
  }

  const totalBytesReclaimed = toDelete.reduce(
    (sum, d) => sum + d.artifact.sizeInBytes,
    0,
  );

  return { toDelete, toRetain, totalBytesReclaimed, dryRun };
}

export interface PlanSummary {
  deletedCount: number;
  retainedCount: number;
  totalBytesReclaimed: number;
  dryRun: boolean;
}

/** Produces a compact human/CI-readable summary of a deletion plan. */
export function summarizePlan(plan: DeletionPlan): PlanSummary {
  return {
    deletedCount: plan.toDelete.length,
    retainedCount: plan.toRetain.length,
    totalBytesReclaimed: plan.totalBytesReclaimed,
    dryRun: plan.dryRun,
  };
}
