// Core retention-policy evaluation logic.
//
// Rules are applied in order:
//   1. keep-latest-N-per-workflow: always keep the N most recent artifacts for each workflow.
//   2. max-age: delete anything older than maxAgeDays (unless protected by rule 1).
//   3. max-total-size: once remaining artifacts exceed maxTotalSizeBytes, delete the oldest
//      surplus first (unless protected by rule 1).

import type {
  Artifact,
  ArtifactDecision,
  CleanupPlan,
  RetentionPolicy,
} from "./types";

export interface BuildCleanupPlanOptions {
  /** Reference "current time" for age calculations. Defaults to `new Date()`. */
  now?: Date;
  /** If true, no artifacts are actually deleted; the plan is still fully computed. */
  dryRun?: boolean;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Rejects nonsensical policy values with a message naming the offending field. */
function validatePolicy(policy: RetentionPolicy): void {
  if (policy.maxAgeDays !== undefined && policy.maxAgeDays < 0) {
    throw new Error(`Invalid retention policy: maxAgeDays must be >= 0, got ${policy.maxAgeDays}`);
  }
  if (policy.maxTotalSizeBytes !== undefined && policy.maxTotalSizeBytes < 0) {
    throw new Error(
      `Invalid retention policy: maxTotalSizeBytes must be >= 0, got ${policy.maxTotalSizeBytes}`
    );
  }
  if (policy.keepLatestPerWorkflow !== undefined && policy.keepLatestPerWorkflow < 0) {
    throw new Error(
      `Invalid retention policy: keepLatestPerWorkflow must be >= 0, got ${policy.keepLatestPerWorkflow}`
    );
  }
}

export function buildCleanupPlan(
  artifacts: Artifact[],
  policy: RetentionPolicy,
  options: BuildCleanupPlanOptions = {}
): CleanupPlan {
  validatePolicy(policy);

  const now = options.now ?? new Date();
  const dryRun = options.dryRun ?? false;

  // Track per-artifact decisions by id so later rules can see earlier "keep" protections.
  const decisions = new Map<string, ArtifactDecision>();
  for (const artifact of artifacts) {
    decisions.set(artifact.id, { artifact, keep: true });
  }

  const protectedIds = computeProtectedIds(artifacts, policy.keepLatestPerWorkflow);

  if (policy.maxAgeDays !== undefined) {
    applyMaxAge(decisions, protectedIds, policy.maxAgeDays, now);
  }

  if (policy.maxTotalSizeBytes !== undefined) {
    applyMaxTotalSize(decisions, protectedIds, policy.maxTotalSizeBytes);
  }

  const ordered = artifacts.map((a) => decisions.get(a.id)!);
  const toDelete = ordered.filter((d) => !d.keep).map((d) => d.artifact);
  const toRetain = ordered.filter((d) => d.keep).map((d) => d.artifact);
  const spaceReclaimedBytes = toDelete.reduce((sum, a) => sum + a.sizeBytes, 0);

  return {
    decisions: ordered,
    toDelete,
    toRetain,
    summary: {
      totalArtifacts: artifacts.length,
      retainedCount: toRetain.length,
      deletedCount: toDelete.length,
      spaceReclaimedBytes,
      dryRun,
    },
  };
}

/** Returns the set of artifact ids that must always be kept due to keep-latest-N-per-workflow. */
function computeProtectedIds(
  artifacts: Artifact[],
  keepLatestPerWorkflow: number | undefined
): Set<string> {
  const protectedIds = new Set<string>();
  if (!keepLatestPerWorkflow || keepLatestPerWorkflow <= 0) {
    return protectedIds;
  }

  const byWorkflow = new Map<string, Artifact[]>();
  for (const artifact of artifacts) {
    const list = byWorkflow.get(artifact.workflowName) ?? [];
    list.push(artifact);
    byWorkflow.set(artifact.workflowName, list);
  }

  for (const list of byWorkflow.values()) {
    const sorted = [...list].sort(
      (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    );
    for (const artifact of sorted.slice(0, keepLatestPerWorkflow)) {
      protectedIds.add(artifact.id);
    }
  }

  return protectedIds;
}

function applyMaxAge(
  decisions: Map<string, ArtifactDecision>,
  protectedIds: Set<string>,
  maxAgeDays: number,
  now: Date
): void {
  for (const decision of decisions.values()) {
    if (protectedIds.has(decision.artifact.id)) continue;
    const ageMs = now.getTime() - new Date(decision.artifact.createdAt).getTime();
    if (ageMs > maxAgeDays * MS_PER_DAY) {
      decision.keep = false;
      decision.reason = "max-age";
    }
  }
}

function applyMaxTotalSize(
  decisions: Map<string, ArtifactDecision>,
  protectedIds: Set<string>,
  maxTotalSizeBytes: number
): void {
  // Consider only artifacts still marked "keep" going into this rule, oldest-first,
  // and evict the oldest non-protected ones until we're under budget.
  const stillKept = [...decisions.values()]
    .filter((d) => d.keep)
    .sort(
      (a, b) =>
        new Date(a.artifact.createdAt).getTime() - new Date(b.artifact.createdAt).getTime()
    );

  let totalSize = stillKept.reduce((sum, d) => sum + d.artifact.sizeBytes, 0);

  for (const decision of stillKept) {
    if (totalSize <= maxTotalSizeBytes) break;
    if (protectedIds.has(decision.artifact.id)) continue;
    decision.keep = false;
    decision.reason = "max-total-size";
    totalSize -= decision.artifact.sizeBytes;
  }
}
